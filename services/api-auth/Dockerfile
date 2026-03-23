FROM registry.suse.com/bci/openjdk-devel:21 AS builder

RUN zypper --non-interactive install maven

WORKDIR /build
COPY pom.xml ./pom.xml
RUN mvn -N install -q -B
COPY api-auth/pom.xml ./api-auth/pom.xml
RUN mvn -f api-auth/pom.xml dependency:go-offline -q -B
COPY api-auth/src ./api-auth/src
RUN mvn -f api-auth/pom.xml package -DskipTests -q -B

FROM registry.suse.com/bci/openjdk:21

WORKDIR /app

COPY --from=builder /build/api-auth/target/*.jar app.jar

RUN useradd -r -u 1001 -g root appuser && \
    mkdir -p /app/config && \
    chown -R appuser:root /app

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:8080/actuator/health || exit 1

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseZGC -XX:+ZGenerational"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar --spring.config.additional-location=optional:file:/app/config/"]
