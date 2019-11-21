FROM java:8-alpine
MAINTAINER Felipe Vinturini <felipe.vinturini@capco.com>
ADD target/hystrix-dashboard-service.jar hystrix-dashboard-service.jar
ENTRYPOINT ["java", "-jar", "/hystrix-dashboard-service.jar"]
EXPOSE 9090
