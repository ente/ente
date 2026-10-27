FROM golang:1.26.10-alpine3.23 AS builder
ENV CGO_ENABLED=0

WORKDIR /etc/ente/

COPY go.mod .
COPY go.sum .
RUN go mod download

COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
  go build -o ente-cli main.go

FROM alpine:3.22
COPY --from=builder /etc/ente/ente-cli .

ARG GIT_COMMIT
ENV GIT_COMMIT=$GIT_COMMIT

CMD ["./ente-cli"]
