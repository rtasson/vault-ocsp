FROM golang:1.16-alpine

ADD . /go/src/github.com/rtasson/vault-ocsp
WORKDIR /go/src/github.com/rtasson/vault-ocsp
RUN go build -o vault-ocsp

FROM alpine:latest
COPY --from=0 /go/src/github.com/rtasson/vault-ocsp /usr/local/bin/
RUN addgroup -S vault-ocsp && \
    adduser -S -G vault-ocsp vault-ocsp
USER vault-ocsp
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/vault-ocsp"]
