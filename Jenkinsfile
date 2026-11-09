pipeline {
    agent { label 'order-api-windows' }
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        skipStagesAfterUnstable()
        timestamps()
        timeout(time: 20, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }
    parameters {
        string(name: 'DEPLOY_DIR', defaultValue: 'C:\\apps\\order-api', description: 'Persistent application directory outside the Jenkins workspace')
        string(name: 'APP_PORT', defaultValue: '8080', description: 'Spring Boot HTTP port')
    }
    stages {
        stage('Pull GitHub source') {
            steps { checkout scm }
        }
        stage('Compile, test and package') {
            steps { bat 'call mvnw.cmd -B -ntp clean verify' }
            post {
                always {
                    junit testResults: 'target/surefire-reports/TEST-*.xml', allowEmptyResults: false
                }
                success {
                    archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
                }
            }
        }
        stage('Deploy and start Spring Boot') {
            steps {
                withEnv(['JENKINS_NODE_COOKIE=order-api-service']) {
                    powershell '''
                        & ./scripts/Deploy-SpringBoot.ps1 -DeployDirectory $env:DEPLOY_DIR -Port ([int]$env:APP_PORT)
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'deployment-logs/*', allowEmptyArchive: true
                }
            }
        }
    }
    post {
        always {
            echo "Build result: ${currentBuild.currentResult}"
            echo "Status API: ${env.BUILD_URL}api/json"
            echo "Build logs: ${env.BUILD_URL}consoleText"
        }
    }
}
