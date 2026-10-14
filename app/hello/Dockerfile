FROM golang:1.27-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /hello ./cmd/hello

FROM gcr.io/distroless/static-debian12:nonroot
# Kamal refuses images without a `service` label matching config/deploy.yml `service:`
LABEL service="hello"
COPY --from=build /hello /hello
EXPOSE 3000
USER nonroot
ENTRYPOINT ["/hello"]
