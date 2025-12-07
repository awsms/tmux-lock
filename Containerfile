FROM alpine:latest

WORKDIR /app
COPY . ./

# Ensure restore step reads our bindings again
COPY ./tests/tmux.conf /root/.tmux.conf

# Minimal toolchain for tests
RUN apk update && apk add --no-cache bash tmux expect grep sed coreutils

# use a sane TERM by default
ENV TERM="tmux-256color"

# put our test tmux.conf where we can point tmux at it
CMD ["/app/tests/test_tmux_lock.sh"]
