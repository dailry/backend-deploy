# 백엔드 배포 프로세스

## GithubAction

다일리는 CI/CD 도구로 깃허브액션을 사용합니다. [(워크플로우 확인하기)](https://github.com/dailry/dailry/blob/develop/.github/workflows/backend-dev-cicd.yml)

깃허브액션 워크플로우에서는 다음과 일들이 이루어 집니다. 

1. jar 파일 빌드
2. jar 파일으로 도커 이미지를 빌드하고 도커 허브에 push
3. self-hosted runner로 EC2 인스턴스에 접근해서 배포 스크립트 (deploy.sh) 실행

도커 허브에 푸쉬한 이미지는 private repository에 저장되며, 태그를 이용해서 dev버전과 prod버전을 구분합니다. 

이 외에 태그에는 해당 이미지 버전을 구분하기 쉽도록 timestamp 값을 추가해서 관리합니다.

추가로 배포 스크립트를 실행할 때 끌어올 이미지 정보를 알아내기 위해 dockrhub_username 과 태그에서 사용한 timestamp 값을 주입합니다.

(도커 registry를 이용해 별도의 private registry를 구축한다면 좋겠지만, 그럴 여력이 되지않아 도커 허브의 private repo를 이용합니다.)

## 무중단 배포와 nginx

간단하고 저렴하게 무중단 배포를 하기 위해 nginx를 사용해서 블루 그린 배포를 구현했습니다.

![image](https://github.com/dailry/backend-deploy/assets/129571789/8536e301-3a9d-4619-95dd-86bc4d9f2153)

![image](https://github.com/dailry/backend-deploy/assets/129571789/beeaa418-e537-42e0-8f01-0117d51a2ec0)

![image](https://github.com/dailry/backend-deploy/assets/129571789/756c8ccb-eea9-48a2-a521-5b364f408732)

무중단 배포는 위의 그림과 같이 진행이 됩니다. 정리하면 아래와 같습니다.

1. 기존 버전은 호스트의 8081 포트와 연결되어 있고, NGINX는 들어오는 요청을 8081 포트로 보냅니다.
2. 새로운 버전의 컨테이너를 호스트의 8082 포트와 연결합니다.
3. 새로운 버전의 컨테이너가 완전히 실행되면 NGINX는 들어오는 요청을 8082 포트로 보냅니다.
4. 구 버전을 중지시킵니다.

## nginx 설정 관리

nginx를 설치하게 되면  `/etc/nginx/sites-available/default` 에서 들어오는 요청을 어떻게 처리할지 설정을 할 수 있습니다.

하지만 그전에 변수 파일을 하나 만들어야 합니다.

```
sudo vi /etc/nginx/conf.d/service-url.inc
```
그리고 아래 코드를 입력합니다.

```
set $service_url http://127.0.0.1:8081;
```

작업을 완료했으면 `/etc/nginx/sites-available/default` 파일을 열어서 아래와 같이 설정을 해줍니다. 

```
sudo vi /etc/nginx/sites-available/default
```

![image](https://github.com/dailry/backend-deploy/assets/129571789/d0a3b5fd-15c4-402a-9ada-97e20003592a)

```
    include /etc/nginx/conf.d/service-url.inc;

    location / {
            proxy_pass $service_url;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $http_host;
    }
```

- `include /etc/nginx/conf.d/service-url.inc;` 
    
    - /etc/nginx/conf.d/service-url.inc 파일을 include 합니다.

    -  저희가 아까 작성한 service-url.inc에 있는 변수($service_url)를 사용할 수 있습니다.
 
    -  **새로운 버전의 배포가 완료되었을 때 $service_url 의 값을 조작하여 nginx의 proxy_pass 설정을 변경하면 됩니다.**

- `proxy_pass $service_url;`

   - 요청을 어느 경로로 보낼지 설정합니다. 
    
   - 예를들어 `proxy_pass http://localhost:8081;` 이면 로컬호스트의 8081경로로 요청을 전달합니다.

   - **새로운 버전의 배포가 완료되었을 때 $service_url 의 값을 조작하여 nginx의 proxy_pass 설정을 변경하면 됩니다.**

- `proxy_set_header ... ` 
    
    - 요청을 전송할 때 추가적인 헤더를 설정합니다.

## docker-compose.yml

도커 컨테이너의 실행을 보다 깔끔하게 관리하기 위해 도커 컴포즈를 이용하였습니다. [(도커-컴포즈-파일-확인)](https://github.com/dailry/backend-deploy/blob/main/docker-compose.yml)

Docker Compose는 여러 개의 도커 컨테이너를 관리할 때 사용하는데, YML파일 안에서 컨테이너의 여러 설정들을 추가로 관리할 수 있어서 편리합니다. 

저희는 컨테이너를 여러개 띄워서 관리하는 것은 아니지만, 위의 블루-그린-배포 에서 블루 컨테이너와 그린 컨테이너를 구분하기 위해서 사용합니다.

**(앞의 그림과는 반대로 호스트의 8081포트와 연결된 것을 블루, 호스트의 8082포트와 연결된 것을 그린 으로 되어있으니 유의해주세요.)**


## .env 파일

도커 컴포즈파일을 보면 이상한 부분이 있습니다. 

### ${DAILRY_IMAGE}

서비스의 이미지가 `${DAILRY_IMAGE}` 와 같은 변수로 되어있습니다.

별도의 태그를 안 붙이고, latest 태그로 덮어쓰는 방식으로 사용하면 이런 조잡한 짓을 할 필요가 없었을 텐데..... 

태그를 이용해 dev버전과 prod버전을 하나의 도커 허브 repository에서 관리 하려다 보니,

배포 스크립트에서 어떠한 이미지를 실행해야 하는지 docker-compose.yml에 알려줘야 했습니다. 

그래서 변수로 설정하고 이후에 배포 스크립트에서 배포 시점에 `${DAILRY_IMAGE}` 값을 조작합니다.

**참고로 ${DAILRY_IMAGE}와 같이 도커 컴포즈에 있는 변수 값들은 동일 디렉토리에 있는 .env 에 등록된 변수 값으로 치환됩니다.**

### env_file : -env

그리고 해당 컨테이너를 실행할 때, 환경변수 값을 셋팅할 필요가 있었는데요.

그 이유는 `application-xxx.yml` 파일에서 보안상 중요한 정보를 (Oauth2 secret Id, JWT Secret, SMTP 계정정보 등) 환경 변수로 주입받도록 해놓았기 때문입니다. 

ex) `client-secret: ${OAUTH_GOOGLE_CLIENT_SECRET}`

위와 같이 절대 노출되어선 안되는 정보들은 되도록 private 하게 서버에서만 관리하는 것이 좋을 것 같아 이렇게 관리를 하였습니다.

### .env

그래서 결론적으로 .env파일은 다음과 같이 두 부분으로 나뉘어 작성되어 있습니다.

```
#application.yml 설정 정보
...
DATASOURCE_URL=??????
DATASOURCE_USERNAME=?????
DATASOURCE_PASSWORD=?????
OAUTH_GOOGLE_CLIENT_SECRET=?????
...

#docker-compose.yml에서 사용하는 이미지 변수, deploy.sh 에서 동적으로 값을 변경
DAILRY_IMAGE=!@#$%^
```

## 배포 스크립트 (deploy.sh)

배포 스크립트에 주석과 `echo`문을 통해서 최대한 정리를 했기 때문에, 의아한 부분이 있을 것 같은 부분만 설명하겠습니다.

### sed-i ...?
```bash
sed -i "s|^DAILRY_IMAGE=.*|DAILRY_IMAGE=${NEW_VERSION_IMAGE}|" /home/ubuntu/.env
sudo docker-compose up -d $NEW_SERVICE
sed -i "s|^DAILRY_IMAGE=.*|DAILRY_IMAGE=!@#$%!@#$%|" /home/ubuntu/.env
```

sed -i 를 이용해서 `.env` 파일에 있는 `DAILRY_IMAGE=????` 값을 `DAILRY_IMAGE=$NEW_VERSION_IMAGE`로 변경합니다.

> **${DAILRY_IMAGE}와 같이 도커 컴포즈에 있는 변수 값들은 동일 디렉토리에 있는 .env 에 등록된 변수 값으로 치환됩니다.** 

라고 한것 기억하시나요? 도커 컴포즈에 있는 DAILRY_IMAGE 값을 설정하기 위해 .env파일에 있는 DAILRY_IMAGE의 값을 변경합니다.

### sleep

```bash
sleep 45;
```

어플리케이션이 커져서 컨테이너가 온전히 실행되는데 보통 2~30초정도 걸리더라구요. 

넉넉하게 45초로 설정하고 온전히 실행되는동안 기다립니다.

### nginx proxy pass 변경

```bash
if sudo docker ps | grep -q ${NEW_SERVICE}; then               #새로운 버전이 실행되었는지 확인
  echo "새로운 버전의 컨테이너가 실행되었습니다... nginx의 proxy_pass를 변경합니다...."
  echo "set \$service_url http://127.0.0.1:${DEPLOY_PORT};" |sudo tee /etc/nginx/conf.d/service-url.inc
  sudo service nginx reload
  echo "새로운 버전의 배포가 완료되었습니다."
```

> **새로운 버전의 배포가 완료되었을 때 $service_url 의 값을 조작하여 nginx의 proxy_pass 설정을 변경하면 됩니다.**

라고 했었는데요. 요게 해당부분입니다. nginx의 proxy_pass를 변경했으면 `sudo service nginx reload` 를 통해 꼭 !! reload 해주어야 합니다.

### 이전 버전 이미지 삭제

```bash
  if [ -n "${CURRENT_SERVICE}" ]; then         #CUREENT_SERVICE가 존재 한다면 이전버전을 종료
    echo "이전 버전을 중지합니다..."
    OLD_IMAGE=$(docker ps -a --filter "name=${CURRENT_SERVICE}" --format "{{.Image}}")
    sudo docker-compose down $CURRENT_SERVICE
    echo "이전 버전의 이미지를 삭제합니다."
    sudo docker rmi $OLD_IMAGE
  else
    exit 0            #CURRENT_SERVICE가 존재하지 않으면 바로 종료
  fi
```

기본 태그인 `latest` 가 아니라, 별도의 태그를 이용하기 때문에 이미지가 계속 서버에 쌓이게 됩니다. 

이미지가 용량이 500MB정도 되서 꽤나 부담이 되었고, 이전버전의 이미지는 삭제해주는 작업이 필요했습니다.
