FROM ghcr.io/irondragonservices/iron-alpine:3
# mime.types is the one thing under /etc/nginx worth keeping; the packaged
# nginx.conf is replaced by ours and the rest is state nginx cannot write to
# anyway.
RUN apk add --no-cache nginx \
  && find /etc/nginx -mindepth 1 ! -name mime.types -delete \
  && rm -rf /var/cache/nginx /var/log/nginx \
  && echo '<h1>iron-alpine</h1>' > "$DATA_DIR/index.html"

COPY nginx.conf $CONF_DIR/

RUN $APP_DIR/post-install.sh

EXPOSE 8080
USER $APP_USER
CMD ["nginx", "-c", "/app/conf/nginx.conf", "-p", "/app", "-e", "/dev/stderr"]
