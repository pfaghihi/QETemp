pipeline {
    agent any
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        skipStagesAfterUnstable()
        timestamps()
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }
    stages {
        stage('Checkout GitHub') {
            steps { checkout scm }
        }
        stage('Compile, test and package') {
            steps {
                script {
                    if (isUnix()) {
                        sh 'sh ./mvnw -B -ntp clean verify'
                    } else {
                        bat 'call mvnw.cmd -B -ntp clean verify'
                    }
                }
            }
            post {
                always {
                    junit testResults: 'target/surefire-reports/TEST-*.xml', allowEmptyResults: false
                }
                success {
                    archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
                }
            }
        }
    }
    post {
        always {
            echo "Build result: ${currentBuild.currentResult}"
            echo "Status: ${env.BUILD_URL}api/json"
            echo "Console log: ${env.BUILD_URL}consoleText"
        }
    }
}
