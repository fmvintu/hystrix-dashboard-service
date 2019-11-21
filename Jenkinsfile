openshift.withCluster() {
  env.SERVICE_PROJECTS = "hystrix-dashboard-service"
  env.ARTIFACT_FOLDER = "all_targets"
  env.NAMESPACE = openshift.project()
  env.POM_FILE = env.BUILD_CONTEXT_DIR ? "${env.BUILD_CONTEXT_DIR}/pom.xml" : "pom.xml"
  env.APP_NAME = "${JOB_NAME}".replaceAll(/-build.*/, '')

  env.DISCOVERY_URL_ENV = "DISCOVERY_URL=http://discovery-service:8761"
  env.DEV_PROJECT = "spring-cloud-demo-dev"
  env.DEV_TAG = "latest"
  env.PROD_PROJECT = "spring-cloud-demo"
  env.PROD_TAG = "latestProd"
  env.DNS_SUFFIX = "3.134.70.57.xip.io"

  env.FORCE_RECREATE_DEV = "false"
  
  Closure create_route = { oc_app, String service_name, String project ->
                            def app_svc = openshift.selector('svc', "${service_name}");
                            def service_port = app_svc.object().spec.ports.port[0];
                            def service_route = "${service_name}-${project}.${DNS_SUFFIX}";
                            
                            println("Creating route for service: [${service_name}][${service_port}] - [${service_route}]");
                            
                            oc_app.narrow("svc").expose("--name=${service_name}", "--port=${service_port}", "--hostname=${service_route}");
                        }
  
  services_bc_lst = []
  services_bc_lst.addAll(SERVICE_PROJECTS.split(','));
  svc_needs_route = ["hystrix-dashboard-service":create_route, "discovery-service":create_route, "gateway-service":create_route]
  
  echo "Starting Pipeline - Current NS: [${env.NAMESPACE}] Services: [${services_bc_lst}] Needs Route: [${svc_needs_route}]"
}

pipeline {
  // Use Jenkins Maven slave
  // Jenkins will dynamically provision this as OpenShift Pod
  // All the stages and steps of this Pipeline will be executed on this Pod
  // After Pipeline completes the Pod is killed so every run will have clean
  // workspace
  agent {
    label 'maven'
  }

  // Pipeline Stages start here
  // Requeres at least one stage
  stages {
    // Checkout source code
    // This is required as Pipeline code is originally checkedout to
    // Jenkins Master but this will also pull this same code to this slave
    stage('Git Checkout') {
      steps {
        // Turn off Git''s SSL cert check, uncomment if needed
        // sh 'git config --global http.sslVerify false'
        git url: "${APPLICATION_SOURCE_REPO}", branch: "${APPLICATION_SOURCE_REF}"
      }
    }

    // Run Maven build, skipping tests
    stage('Build'){
      steps {
        sh "mvn -B clean install -DskipTests=true -f ${POM_FILE}"
      }
    }

    // Run Maven unit tests
    stage('Unit Test'){
      steps {
        sh "mvn -B test -f ${POM_FILE}"
      }
    }

    stage('Store Artifact'){
      steps{
        script{
            services_bc_lst.each { APPLICATION_NAME ->
                def safeBuildName  = "${APPLICATION_NAME}_${BUILD_NUMBER}",
                    artifactFolder = "${ARTIFACT_FOLDER}",
                    fullFileName   = "${safeBuildName}.tar.gz",
                    applicationZip = "${artifactFolder}/${fullFileName}"
                    applicationDir = ["target/${APPLICATION_NAME}.jar",
                                      "Dockerfile",
                                      ].join(" ");
                def needTargetPath = !fileExists("${artifactFolder}")
                if (needTargetPath) {
                    sh "mkdir ${artifactFolder}"
                }
                sh "tar --directory=${APPLICATION_NAME} -czvf ${applicationZip} ${applicationDir}"
                archiveArtifacts artifacts: "${applicationZip}", excludes: null, onlyIfSuccessful: true         
            }
        }
      }
   }

    stage('Create Image Builder') {
        when {
            expression {
              openshift.withCluster() {
                openshift.withProject(DEV_PROJECT) {                    
                    services_bc = services_bc_lst.findAll{ !openshift.selector("bc", it).exists() };
                    
                    return services_bc;
                  }
               }
            }
        }
        
        steps {
            script {
                openshift.withCluster() {
                    openshift.withProject(DEV_PROJECT) {
                        def services_bc = services_bc_lst.findAll{ svc -> !openshift.selector("bc", svc).exists() };
                        services_bc.each { service ->
                            openshift.newBuild("--name=${service}", "--docker-image=docker.io/java:8-alpine", "--binary=true")
                        }
                    }
                }
            }
        }
    }
    
    stage('Build Image') {
      steps {
          script {
              openshift.withCluster() {
                openshift.withProject(env.DEV_PROJECT) {
                    services_bc_lst.each { APPLICATION_NAME -> 
                        println("Building application image: [${APPLICATION_NAME}]");
                        openshift.selector("bc", "${APPLICATION_NAME}").startBuild("--from-archive=${ARTIFACT_FOLDER}/${APPLICATION_NAME}_${BUILD_NUMBER}.tar.gz", "--wait=true")
                    }
                }
              }
          }
      }
    }
    
    stage('Deploy to Dev') {
      when {
          expression {
            openshift.withCluster() {
              openshift.withProject(env.DEV_PROJECT) {
                def services_bc = services_bc_lst.findAll{ svc -> !openshift.selector("dc", svc).exists() };

                def recreate_env = services_bc || FORCE_RECREATE_DEV.toBoolean();
                
                println("Recreate: [${DEV_PROJECT}] environment: [${recreate_env}]");
                
                return recreate_env;
              }
            }
        }
      }
      
      steps {
        script {
            openshift.withCluster() {
                openshift.withProject(env.DEV_PROJECT) {
                    services_bc = services_bc_lst.findAll{ svc -> !openshift.selector("dc", svc).exists() } as Set;
					println("Services to recreate[${FORCE_RECREATE_DEV}]: [${services_bc}]");
					
                    if(FORCE_RECREATE_DEV.toBoolean()) {
                        services_bc.addAll(services_bc_lst);
                    }
					
					println("Services to recreate[${FORCE_RECREATE_DEV}]: [${services_bc}]");
                    
                    services_bc.each { APPLICATION_NAME -> 
                        println("Deploy application: [${APPLICATION_NAME}] to development");
                        openshift.selector('dc', "${APPLICATION_NAME}").delete("--ignore-not-found")
                        openshift.selector('svc', "${APPLICATION_NAME}").delete("--ignore-not-found")
                        openshift.selector('route', "${APPLICATION_NAME}").delete("--ignore-not-found")                     
                        
                        def app = openshift.newApp("${APPLICATION_NAME}:${DEV_TAG}", "-e=${DISCOVERY_URL_ENV}");
                        def dc = openshift.selector("dc", "${APPLICATION_NAME}");
                        while (dc.object().spec.replicas != dc.object().status.availableReplicas) {
                            println("Replicas - spec: [${dc.object().spec.replicas}] - available: [${dc.object().status.availableReplicas}]")
                            sleep 5
                        }
                        
                        def needs_route = svc_needs_route.containsKey(APPLICATION_NAME);
                        println("Service: [${APPLICATION_NAME}] needs route: [${needs_route}]");
                        
                        svc_needs_route?.get(APPLICATION_NAME)?.call(app, APPLICATION_NAME, DEV_PROJECT);
                    }
                 }
              }
          }
      }
    }

    stage('Promote to Production?') {
      steps {
          timeout(time:15, unit:'MINUTES') {
               input message: "Promote to Production?", ok: "Promote"
          }
          script {
              openshift.withCluster() {
                  //openshift.verbose();
                  services_bc_lst.each { APPLICATION_NAME -> 
                    println("Promoting to Production: [${PROD_PROJECT}][${APPLICATION_NAME}] with tag: [${PROD_TAG}]");
                    openshift.tag("${DEV_PROJECT}/${APPLICATION_NAME}:${DEV_TAG}", "${PROD_PROJECT}/${APPLICATION_NAME}:${PROD_TAG}")
                  }
              }
            }
       }
    }
    
    stage('Rollout to Production') {
      steps {
          script {
                //openshift.verbose();
                openshift.withCluster() {
                  openshift.withProject(env.PROD_PROJECT) {
                    services_bc_lst.each { APPLICATION_NAME ->                     
                        def dc_exists = openshift.selector('dc', "${APPLICATION_NAME}").exists();
                        if (openshift.selector('dc', "${APPLICATION_NAME}").exists()) {
                            println("Promoting to Production: [${APPLICATION_NAME}] deleting: [dc][svc][route] and recreating");
                            openshift.selector('dc', "${APPLICATION_NAME}").delete("--ignore-not-found")
                            openshift.selector('svc', "${APPLICATION_NAME}").delete("--ignore-not-found")
                            openshift.selector('route', "${APPLICATION_NAME}").delete("--ignore-not-found")
                        }
                        def app = openshift.newApp("${APPLICATION_NAME}:${PROD_TAG}", "-e=${DISCOVERY_URL_ENV}");
                        svc_needs_route?.get(APPLICATION_NAME)?.call(app, APPLICATION_NAME, PROD_PROJECT);
                 }
               }
             }
          }
      }
    }
  }
}
