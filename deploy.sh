#!/bin/bash

cd /home/ubuntu/cicd

APP_NAME="practice"

# NGINX 설정 관련
NGINX_CONF_PATH="/etc/nginx"
BLUE_CONF="blue.conf"
GREEN_CONF="green.conf"
DEFAULT_CONF="nginx.conf"
MAX_RETRIES=3

# 활성화된 서비스 확인 및 스위칭 대상 결정
determine_target() {
  if docker-compose -f docker-compose.yml ps | grep -q "app_blue.*Up"; then
    TARGET="green"
    OLD="blue"
  elif docker-compose -f docker-compose.yml ps | grep -q "app_green.*Up"; then
    TARGET="blue"
    OLD="green"
  else
    TARGET="blue"  # 첫 실행 시 기본값
    OLD="none"
  fi

  echo "TARGET: $TARGET"
  echo "OLD: $OLD"
}

# 헬스체크 실패 시 롤백 처리
health_check() {
  local URL=$1
  local RETRIES=0
  local ORIGINAL_TARGET=$TARGET

  while [ $RETRIES -lt $MAX_RETRIES ]; do
    echo "Checking service at $URL... (attempt: $((RETRIES + 1)))"
    sleep 3

    CONTAINER_RUNNING=$(docker ps --filter "name=app_$TARGET" --format '{{.Names}}')

    if [ "$CONTAINER_RUNNING" = "app_$TARGET" ]; then
      echo "$TARGET container is running."
      return 0
    else
      echo "$TARGET container is not running."
    fi

    RETRIES=$((RETRIES + 1))
  done

  echo "Health check failed after $MAX_RETRIES attempts."
  echo "Rolling back to the original target: $ORIGINAL_TARGET"
  TARGET=$ORIGINAL_TARGET
  echo "Rolled back TARGET: $TARGET"
  echo "Failed health check for $TARGET container" > /home/ubuntu/cicd/health_check_failure.log
  exit 1
}

# NGINX 설정 스위칭 함수
switch_nginx_conf() {
  if [ "$TARGET" = "blue" ]; then
    sudo cp "${NGINX_CONF_PATH}/${BLUE_CONF}" "${NGINX_CONF_PATH}/${DEFAULT_CONF}"
  else
    sudo cp "${NGINX_CONF_PATH}/${GREEN_CONF}" "${NGINX_CONF_PATH}/${DEFAULT_CONF}"
  fi

  echo "Reloading NGINX configuration..."
  nginx -s reload
}

# 이전 컨테이너 종료 함수
down_old_container() {
  if [ "$OLD" != "none" ]; then
    echo "Stopping old container: $OLD"
    sudo docker stop "app_$OLD"
  fi
}

# 메인 실행 로직
main() {
  determine_target

  echo "Starting $TARGET container..."
  docker-compose -p $APP_NAME -f docker-compose.yml up -d "app_$TARGET"

  if [ "$TARGET" = "blue" ]; then
    health_check "http://127.0.0.1:8080/actuator/health"
  else
    health_check "http://127.0.0.1:8081/actuator/health"
  fi

  switch_nginx_conf
  down_old_container

  echo "Deployment to $TARGET completed successfully!"
  echo "Cleaning up dangling Docker images..."
  docker image prune -f
}

main
