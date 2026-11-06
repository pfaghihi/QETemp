pipeline {
    agent { label 'windows' }

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        skipStagesAfterUnstable()
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '5'))
    }

    parameters {
        string(name: 'APP_PORT', defaultValue: '8081', description: 'Order API port on the Windows agent')
    }

    stages {
        stage('Checkout GitHub') {
            steps { checkout scm }
        }
        stage('Compile') {
            steps {
                bat 'java -version'
                bat 'mvnw.cmd -B -ntp clean compile'
            }
        }
        stage('JUnit tests') {
            steps { bat 'mvnw.cmd -B -ntp test' }
            post {
                always {
                    junit testResults: 'target/surefire-reports/TEST-*.xml', allowEmptyResults: false
                }
            }
        }
        stage('Package') {
            steps {
                bat 'mvnw.cmd -B -ntp -DskipTests package'
                archiveArtifacts artifacts: 'target/order-api-*.jar', fingerprint: true
            }
        }
        stage('Deploy and start') {
            steps {
                powershell '''
                    $ErrorActionPreference = 'Stop'
                    & .\scripts\Deploy-OrderApi.ps1 -Port ([int]$env:APP_PORT) -DeployDirectory "$env:WORKSPACE@deploy"
                '''
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'target/deployment-*.log', allowEmptyArchive: true
            echo "Result: ${currentBuild.currentResult}; console: ${env.BUILD_URL}console"
        }
    }
}
