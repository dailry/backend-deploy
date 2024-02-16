#!/bin/bash

echo "배포 스크립트 실행"
echo "스크립트를 실행할 때 주입받은 변수값 셋팅하기"

DOCKER_HUB_USERNAME=$1
IMAGE_VERSION=$2
NEW_VERSION_IMAGE="$DOCKER_HUB_USERNAME/dailry:dev_$IMAGE_VERSION"

echo "새로운 버전의 이미지 가져오기: $NEW_VERSION_IMAGE"
sudo docker pull $NEW_VERSION_IMAGE

if sudo docker ps | grep -q dailry-blue; then
    echo "블루 서비스가 실행되고 있습니다. (port 8081:8080)"
    CURRENT_SERVICE="dailry-blue"
    NEW_SERVICE="dailry-green"
    DEPLOY_PORT=8082
elif sudo docker ps | grep -q dailry-green; then
    echo "그린 서비스가 실행되고 있습니다. (port 8082:8080) "
    CURRENT_SERVICE="dailry-green"
    NEW_SERVICE="dailry-blue"
    DEPLOY_PORT=8081
else
    echo "현재 실행되고 있는 서비스가 없습니다."
    CURRENT_SERVICE=""
    NEW_SERVICE="dailry-blue"
    DEPLOY_PORT=8081
fi

echo "CURRENT_SERVICE : ${CURRENT_SERVICE}"
echo "NEW_SERVICE : ${NEW_SERVICE}"

echo "새로운 버전의 컨테이너를 실행합니다..."

sed -i "s|^DAILRY_IMAGE=.*|DAILRY_IMAGE=${NEW_VERSION_IMAGE}|" /home/ubuntu/.env
sudo docker-compose up -d $NEW_SERVICE
sed -i "s|^DAILRY_IMAGE=.*|DAILRY_IMAGE=!@#$%!@#$%|" /home/ubuntu/.env

sleep 45;


#이전버전 중지 및 이미지 삭제
if sudo docker ps | grep -q ${NEW_SERVICE}; then               #새로운 버전이 실행되었는지 확인
  echo "새로운 버전의 컨테이너가 실행되었습니다... nginx의 proxy_pass를 변경합니다...."
  echo "set \$service_url http://127.0.0.1:${DEPLOY_PORT};" |sudo tee /etc/nginx/conf.d/service-url.inc
  sudo service nginx reload
  echo "새로운 버전의 배포가 완료되었습니다."

  if [ -n "${CURRENT_SERVICE}" ]; then         #CUREENT_SERVICE가 존재 한다면 이전버전을 종료
    echo "이전 버전을 중지합니다..."
    OLD_IMAGE=$(docker ps -a --filter "name=${CURRENT_SERVICE}" --format "{{.Image}}")
    sudo docker-compose down $CURRENT_SERVICE
    echo "이전 버전의 이미지를 삭제합니다."
    sudo docker rmi $OLD_IMAGE
  else
    exit 0            #CURRENT_SERVICE가 존재하지 않으면 바로 종료
  fi

else
  echo "새로운 버전의 컨테이너가 실행되지 않았습니다."
  exit 1
fi
