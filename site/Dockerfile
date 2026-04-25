# Лёгкий nginx-alpine для отдачи статики.
# Когда дойдём до прода — поставим перед ним Caddy для автоматического TLS.
FROM nginx:1.27-alpine

# Кастомный конфиг с gzip и sane defaults
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Сама статика
COPY index.html /usr/share/nginx/html/
COPY styles.css /usr/share/nginx/html/

EXPOSE 80
