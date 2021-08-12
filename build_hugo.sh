#!/usr/bin/env bash

BINNAME=$0
BINPATH=$(realpath -s "$BINNAME")
REPO_ROOT=$(dirname "$BINPATH")
LIBS_PATH="${REPO_ROOT}/libs"
OGL_PATH="${LIBS_PATH}/opsgang"

HUGO_DIR="${REPO_ROOT}/hugo"
DOCKER_HUGO_REPO="${DOCKER_HUGO_REPO:-klakegg/hugo}"
DOCKER_HUGO_TAG="${DOCKER_HUGO_TAG:-0.83.1-alpine}"
DOCKER_WDIR="/opt/hugo"

# shellcheck disable=SC1090,SC1091
source "$REPO_ROOT/libs/local.bash" || exit 1

cleanup_oldbuild(){
    if [[ -z "${HUGO_DIR:-}" ]] || [[ ! -d "$HUGO_DIR" ]]; then
        e >&2 "Unknown working dir!"
        return 1
    fi

    find "$HUGO_DIR/public" -mindepth 1 -maxdepth 1 ! -name ".gitignore" -exec rm -r -- {} \;
}
check_if_build_run(){
    required_files "${HUGO_DIR}/public/404.html
    ${HUGO_DIR}/public/index.html
    ${HUGO_DIR}/public/index.xml
    ${HUGO_DIR}/public/sitemap.xml
    ${HUGO_DIR}/public/robots.txt
    " || return 1
}

pre(){
    download_libs || return 1
    cleanup_oldbuild || return 1
}

post() {
    i >&2 "Post hook"
    cleanup || return 1
    i >&2 "Done"
}

build_static() {
    i >&2 "Building files"
    docker run --rm -v "$REPO_ROOT/hugo:$DOCKER_WDIR" -w "$DOCKER_WDIR" "$DOCKER_HUGO_REPO:$DOCKER_HUGO_TAG" || return 1
    i >&2 "Checking main output files"
    if ! check_if_build_run; then
        e >&2 "Cannot found the assets"
        return 1
    fi
}
docker_wait_until_healthy() {
    local __id=$1
    local __counter=0

    if [[ -z "${__id:-}" ]]; then
        e >&2 "Docker image ID cannot be empty"
        return 1
    fi
    if [[ "$(docker inspect -f '{{.State.Running}}' "$__id")" != "true" ]]; then
        e >&2 "Container is not running: $__id"
        d >&2 "$(docker ps)"
        return 1
    fi

    while [[ "$(docker inspect -f '{{.State.Health.Status}}' "$__id")" != "healthy" ]]; do
        i >&2 "Waiting for the container [$__counter] ..."
        if [[ "$__counter" -ge 15 ]]; then
            e >&2 "Timed out. Quitting"
            return 1
        fi
        sleep 2
        ((__counter=__counter+1))
    done

}
test_build(){
    local __tmp_file='/tmp/index.html'
    local __id

    rm -f "$__tmp_file"
    docker rm -f hugo >/dev/null 2>&1 || true
    __id=$(docker run --rm --name hugo \
        -v "$REPO_ROOT/hugo:$DOCKER_WDIR" \
        -w "$DOCKER_WDIR" \
        -p 1313:1313 \
        -d \
        --health-cmd 'netstat -tnlp|grep LISTEN|grep 1313' \
        --health-start-period 2s \
        --health-retries 15 \
        --health-interval 2s \
        "$DOCKER_HUGO_REPO:$DOCKER_HUGO_TAG" server || return 1)
    docker_wait_until_healthy "$__id" || return 1

    if ! curl --fail --silent --output "$__tmp_file" http://localhost:1313/; then
        e >&2 "Could not get the index.html"
        return 1
    fi
    if ! grep 'Levent Yalcin' "$__tmp_file"; then
        e >&2 "Could not find the text"
        return 1
    fi

    echo "GIT_USER: $GIT_USER
GIT_INFO: $GIT_INFO
DOCKER_IMAGE: $DOCKER_HUGO_REPO:$DOCKER_HUGO_TAG
TZ: $(date --rfc-email)" > "$HUGO_DIR/public/.version"
    docker rm -f hugo || return 0
}

deploy_files(){
    local __bucket_name
    local __deploy_target_url
    local __rc=0

    i >&2 "Deployment starting"
    if [[ -z "${CI:-}" ]]; then
        yellow_i >&2 "Command is not running under the CI server. Skipping"
        return 0
    fi
    i >&2 "Checking main output files"
    if ! check_if_build_run; then
        e >&2 "Cannot found the assets"
        return 1
    fi
    if [[ "${FORCE_TO_DEPLOY_WITHOUT_PUSHING_CHANGES:-}" = "iswearitisfordevelopmentreasons" ]]; then
        yellow_i >&2 "Please do not use flag unless there is a desperate need for DEBUG or development difficulties"
        yellow_i >&2 "If there is something which makes development harder, find a better solution for that and implement"
        yellow_i >&2 "Better that way!"
    else
        no_unpushed_changes || return 1
    fi

    tf_init || return 1

    cd "$TF_DIR" || return 1
    __bucket_name=$(terraform output --raw bucket_name)
    cd "$REPO_ROOT" || return 1
    __deploy_target_url="s3:\/\/${__bucket_name}"
    required_vars "__bucket_name __deploy_target_url" || return 1

    aws_generate_creds_file > "$HUGO_DIR/.credentials" || return 1
    required_files "$HUGO_DIR/.credentials" || return 1

    [[ -n "${DEBUG:-}" ]] && set -x
    sed --in-place=.bak --regexp-extended "s/^(\s*URL\s*=\s*\").*(\".*$)/\1$__deploy_target_url\2/" "${HUGO_DIR}/config.toml"
    docker run --rm \
        -v "$HUGO_DIR:$DOCKER_WDIR" \
        -e "AWS_SHARED_CREDENTIALS_FILE=$DOCKER_WDIR/.credentials" \
        -w "$DOCKER_WDIR" \
        "$DOCKER_HUGO_REPO:$DOCKER_HUGO_TAG" \
        deploy \
    || __rc=1
    [[ -n "${DEBUG:-}" ]] && set +x
    return $__rc
}

build(){
    pre || return 1

    # shellcheck disable=SC1090,SC1091
    source "$OGL_PATH/opsgang.sourcelibs" || return 1
    git_vars; [[ -z "${GIT_USER:-}" ]] && [[ -n "${GITHUB_ACTOR:-}" ]] && export GIT_USER="$GITHUB_ACTOR"

    pre_run_checks || return 1
    build_static || return 1
    test_build || return 1
    deploy_files || return 1
}

trap post EXIT

build || exit 1
