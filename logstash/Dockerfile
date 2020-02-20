FROM docker.elastic.co/logstash/logstash:7.4.0
RUN rm -f /usr/share/logstash/pipeline/logstash.conf \
    rm -f /usr/share/logstash/pipelines.yml
ADD pipeline/* /usr/share/logstash/pipeline/
ADD config/* /usr/share/logstash/