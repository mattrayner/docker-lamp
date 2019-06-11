FROM phusion/baseimage
MAINTAINER Matthew Rayner <matt@mattrayner.co.uk>

RUN apt-get update && apt-get install -yq curl && apt-get clean

WORKDIR /app

COPY test.sh /app/test.sh
COPY 1604.sh /app/1604.sh
COPY 1804.sh /app/1804.sh
COPY _helpers.sh /app/_helpers.sh
COPY expected/1604-php7.html /app/expected/1604-php7.html
COPY expected/1804-php7.html /app/expected/1804-php7.html

RUN mkdir -p actual/

CMD ["bash", "test.sh"]
