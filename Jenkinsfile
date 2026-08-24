pipeline {
  agent none

  options {
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    timeout(time: 10, unit: 'MINUTES')
    timestamps()
  }

  stages {
    stage('Validate') {
      agent { label 'linux' }
      steps {
        checkout scm
        sh 'bash scripts/verify.sh'
      }
    }
  }
}
