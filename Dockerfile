ARG alpine_tag=latest

FROM alpine:${alpine_tag} AS build

RUN apk add --no-cache alpine-sdk doas \
    && echo 'permit nopass :wheel' >> /etc/doas.conf

RUN adduser -D build \
    && addgroup build abuild \
    && addgroup build wheel \
    && sync

USER build

WORKDIR /home/build
RUN source /etc/os-release \
    && git clone -n --depth=1 --filter=tree:0 https://github.com/alpinelinux/aports.git --branch v\${VERSION_ID} \
    && cd aports \
    && git sparse-checkout set --no-cone main/openssl \
    && git checkout

WORKDIR /home/build/aports/main/openssl
RUN sed -i 's/^\(.*\)enable-ktls \(.*\)$/&\n\1enable-fips \2/' APKBUILD
RUN abuild deps
RUN abuild fetch
RUN abuild unpack
RUN abuild prepare
RUN abuild build

USER root
RUN cd src/openssl-* \
    && make install_sw install_ssldirs install_fips

RUN sed \
      -e 's@^# \(.include \)\(fipsmodule.cnf\)@\1 /etc/ssl/\2@' \
      -e 's@^\[openssl_init\]@&\nalg_section = algorithm_sect@' \
      -e 's@^\[provider_sect\]@&\nbase = base_sect@' \
      -e 's@^# \(fips = fips_sect\)@\1@' \
      -e 's@^# activate = 1@&\n\n[base_sect]\nactivate = 1@' \
      /etc/ssl/openssl.cnf.dist > /etc/ssl/openssl.cnf \
    && echo -e "[algorithm_sect]\ndefault_properties = fips=yes" >> /etc/ssl/openssl.cnf

RUN openssl fipsinstall -config /etc/ssl/openssl.cnf \
    && openssl list -providers -provider fips

FROM alpine:${alpine_tag}

ENV OPENSSL_CONF=/etc/ssl/openssl.cnf
ENV OPENSSL_MODULES=/usr/lib/ossl-modules

COPY --from=build /usr/lib/ossl-modules/fips.so /usr/lib/ossl-modules/fips.so
COPY --from=build /etc/ssl/fipsmodule.cnf /etc/ssl/fipsmodule.cnf
COPY --from=build /etc/ssl/openssl.cnf /etc/ssl/openssl.cnf
