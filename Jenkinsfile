// ---------------------------------------------------------------------------
// TaskApp CI pipeline  (CI = Jenkins,  CD = Argo CD)
//
//   commit -> test -> build -> scan -> push image -> bump tag in Git
//                                                     |
//                                 Argo CD sees the Git change and deploys it
//
// Jenkins never touches the cluster. Git is the single source of truth (GitOps).
// ---------------------------------------------------------------------------
pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    IMAGE_NAME = "${env.DOCKERHUB_USER}/taskapp"
    VALUES_FILE = 'helm/taskapp/values.yaml'
  }

  stages {
    stage('Skip bot commits') {
      // Our own "bump image tag" commit would otherwise trigger an endless loop.
      steps {
        script {
          def msg = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
          if (msg.contains('[skip ci]')) {
            currentBuild.result = 'NOT_BUILT'
            env.SKIP = 'true'
            echo "Commit is a CI tag bump, skipping."
          }
        }
      }
    }

    stage('Set version') {
      when { not { environment name: 'SKIP', value: 'true' } }
      steps {
        script {
          env.SHORT_SHA = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
          // Immutable, traceable tag: build number + commit. Never deploy ":latest".
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.SHORT_SHA}"
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.IMAGE_TAG}"
        }
      }
    }

    stage('Lint & unit tests') {
      when { not { environment name: 'SKIP', value: 'true' } }
      steps {
        // Tests run INSIDE Docker (Dockerfile "test" stage): same env everywhere.
        sh 'docker build --target test -t taskapp-test:${IMAGE_TAG} app/'
      }
    }

    stage('Helm lint') {
      when { not { environment name: 'SKIP', value: 'true' } }
      steps {
        sh 'helm lint helm/taskapp'
        sh 'helm template taskapp helm/taskapp > /dev/null'
      }
    }

    stage('Build image') {
      when { not { environment name: 'SKIP', value: 'true' } }
      steps {
        sh '''
          docker build --target runtime \
            --build-arg APP_VERSION=${IMAGE_TAG} \
            -t ${IMAGE_NAME}:${IMAGE_TAG} app/
        '''
      }
    }

    stage('Security scan (Trivy)') {
      when { not { environment name: 'SKIP', value: 'true' } }
      steps {
        // --exit-code 0 = report only. Flip to 1 to fail the build on HIGH/CRITICAL CVEs.
        sh '''
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:0.76.2 image --severity HIGH,CRITICAL --exit-code 0 \
            --no-progress ${IMAGE_NAME}:${IMAGE_TAG}
        '''
      }
    }

    stage('Push image') {
      when { not { environment name: 'SKIP', value: 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                          usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
          sh '''
            echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
            docker push ${IMAGE_NAME}:${IMAGE_TAG}
            docker logout
          '''
        }
      }
    }

    stage('GitOps: bump image tag') {
      when { not { environment name: 'SKIP', value: 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'github-creds',
                          usernameVariable: 'GH_USER', passwordVariable: 'GH_TOKEN')]) {
          sh '''
            sed -i "s|^  repository: .*|  repository: ${IMAGE_NAME}|" ${VALUES_FILE}
            sed -i "s|^  tag: .*|  tag: \\"${IMAGE_TAG}\\"|" ${VALUES_FILE}
            git config user.email "jenkins@ci.local"
            git config user.name  "Jenkins CI"
            git add ${VALUES_FILE}
            git commit -m "ci: deploy taskapp ${IMAGE_TAG} [skip ci]"
            REPO=$(git config --get remote.origin.url | sed 's|https://||')
            git push "https://${GH_USER}:${GH_TOKEN}@${REPO}" HEAD:main
          '''
        }
      }
    }
  }

  post {
    success { echo "Pushed ${env.IMAGE_NAME}:${env.IMAGE_TAG}. Argo CD will roll it out." }
    failure { echo 'Build failed: check the stage logs above.' }
    always  { sh 'docker image prune -f || true' }
  }
}
