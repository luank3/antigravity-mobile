FROM golang:1.26-alpine AS builder

WORKDIR /src
ENV GOTOOLCHAIN=auto

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/agy-relay ./cmd/agy-relay

FROM alpine:3.21

RUN apk add --no-cache ca-certificates && mkdir -p /data
COPY --from=builder /out/agy-relay /usr/local/bin/agy-relay

VOLUME ["/data"]
EXPOSE 4001/tcp 4001/udp

ENTRYPOINT ["/usr/local/bin/agy-relay", "--identity", "/data/identity.key"]
