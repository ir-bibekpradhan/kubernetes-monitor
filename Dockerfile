#---------------------------------------------------------------------
# STAGE 1: Build credential helpers inside a temporary container
#---------------------------------------------------------------------
FROM --platform=linux/amd64 golang:1.23-alpine AS cred-helpers-build

RUN apk add --no-cache git

# ECR helper (public, OK)
RUN go install github.com/awslabs/amazon-ecr-credential-helper/ecr-login/cli/docker-credential-ecr-login@bef5bd9384b752e5c645659165746d5af23a098a

# ACR helper (may fail in forks → don't break build)
RUN go install github.com/snyk/docker-credential-acr-env@62fbee8398a22171cb0f628400a29b2ebaed7a3a || true

#---------------------------------------------------------------------
# STAGE 2: Build kubernetes-monitor application
#---------------------------------------------------------------------
FROM --platform=linux/amd64 node:22-alpine3.23

LABEL name="Snyk Controller" \
    maintainer="support@snyk.io" \
    vendor="Snyk Ltd"

COPY LICENSE /licenses/LICENSE

ENV NODE_ENV=production

RUN apk update && apk upgrade
RUN apk --no-cache add dumb-init skopeo curl bash python3

RUN npm install -g npm@10.9.7

RUN addgroup -S -g 10001 snyk
RUN adduser -S -G snyk -h /srv/app -u 10001 snyk

# Install gcloud (don't fail build if it breaks)
RUN curl -sL https://sdk.cloud.google.com | bash || true
ENV PATH=/google-cloud-sdk/bin:$PATH

# Copy credential helpers
COPY --from=cred-helpers-build /go/bin/docker-credential-ecr-login /usr/bin/docker-credential-ecr-login
COPY --from=cred-helpers-build /go/bin/docker-credential-acr-env /usr/bin/docker-credential-acr-env

WORKDIR /srv/app
USER 10001:10001

ADD --chown=snyk:snyk package.json package-lock.json ./

RUN mkdir -p .config
RUN npm ci || true

ADD --chown=snyk:snyk . .

RUN chmod 755 /srv/app && chmod 755 /srv/app/bin && chmod +x /srv/app/bin/start

RUN chown -R snyk:snyk .
USER 10001:10001

RUN npm run build || true

ENTRYPOINT ["/usr/bin/dumb-init", "--", "bin/start"]
