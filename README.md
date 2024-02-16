# 백엔드 배포 프로세스

## GithubAction

다일리는 CI/CD 도구로 깃허브액션을 사용합니다. [(워크플로우 확인하기)](https://github.com/dailry/dailry/blob/develop/.github/workflows/backend-dev-cicd.yml)

워크플로우에서는 다음과 일들이 이루어 집니다. 

1. jar 파일 빌드
2. jar 파일으로 도커 이미지를 빌드하고 도커 허브에 push
3. self-hosted runner로 EC2 인스턴스에 접근해서 배포 스크립트 (deploy.sh) 실행

도커 허브에 푸쉬한 이미지는 private repository에 저장되며, 태그를 이용해서 dev버전과 prod버전을 구분합니다.

도커 registry를 이용해 별도의 private registry를 구축한다면 좋겠지만, 그럴 여력이 되지않아 도커 허브의 private repo를 이용합니다.

## 무중단 배포와 nginx

간단하게 무중단 배포를 구현하기 위해 nginx를 사용했습니다.

![image](https://github.com/dailry/backend-deploy/assets/129571789/8536e301-3a9d-4619-95dd-86bc4d9f2153)

![image](https://github.com/dailry/backend-deploy/assets/129571789/beeaa418-e537-42e0-8f01-0117d51a2ec0)

![image](https://github.com/dailry/backend-deploy/assets/129571789/756c8ccb-eea9-48a2-a521-5b364f408732)

무중단 배포는 위의 그림과 같이 진행이 됩니다. 정리하면 아래와 같습니다.

1. 기존 버전은 8081 포트와 연결되어 있고, NGINX는 들어오는 요청을 8081 포트로 보냅니다.
2. 새로운 버전의 컨테이너를 8082 포트와 연결합니다.
3. 새로운 버전의 컨테이너가 완전히 실행되면 NGINX는 들어오는 요청을 8082 포트로 보냅니다.
4. 구 버전을 중지시킵니다.

### nginx 설정 관리

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
 
    -  새로운 버전의 배포가 완료되었을 때 $service_url 의 값을 조작하여 nginx의 proxy_pass 설정을 변경하면 됩니다.

- `proxy_pass $service_url;`

   - 요청을 어느 경로로 보낼지 설정합니다. 
    
   - 예를들어 `proxy_pass http://localhost:8081;` 이면 로컬호스트의 8081경로로 요청을 전달합니다.

   - 저희는 배포를 할 때마다 동적으로 proxy_pass의 값을 바꿔주어야 하므로 변수로 저장합니다.

- `proxy_set_header ... ` 
    
    - 요청을 전송할 때 추가적인 헤더를 설정합니다.


