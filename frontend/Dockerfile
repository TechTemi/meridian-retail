FROM busybox:1.38.0-musl

COPY index.html /www/index.html

EXPOSE 80

CMD ["httpd", "-f", "-p", "80", "-h", "/www"]
