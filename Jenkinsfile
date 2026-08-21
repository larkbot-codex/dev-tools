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
        sh 'shellcheck bashrc.d/*.sh install.sh uninstall.sh test/*.sh'
        sh '''
          set -eu
          for test_script in test/*.sh; do
            bash "$test_script"
          done
        '''
      }
    }
  }
}
