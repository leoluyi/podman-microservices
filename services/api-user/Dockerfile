FROM registry.suse.com/bci/openjdk-devel:21 AS builder

RUN zypper --non-interactive install maven

WORKDIR /build
COPY pom.xml ./pom.xml
RUN mvn -N install -q -B
COPY api-user/pom.xml ./api-user/pom.xml
RUN mvn -f api-user/pom.xml dependency:go-offline -q -B
COPY api-user/src ./api-user/src
RUN mvn -f api-user/pom.xml package -DskipTests -q -B

FROM registry.suse.com/bci/openjdk:21

WORKDIR /app

COPY --from=builder /build/api-user/target/*.jar app.jar

RUN useradd -r -u 1001 -g root appuser && \
    mkdir -p /app/config && \
    chown -R appuser:root /app

USER appuser

EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseZGC -XX:+ZGenerational"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar --spring.config.additional-location=optional:file:/app/config/"]
