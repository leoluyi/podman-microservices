FROM registry.suse.com/bci/openjdk-devel:21 AS builder

RUN zypper --non-interactive install maven

WORKDIR /build
COPY pom.xml ./pom.xml
RUN mvn -N install -q -B
COPY api-order/pom.xml ./api-order/pom.xml
RUN mvn -f api-order/pom.xml dependency:go-offline -q -B
COPY api-order/src ./api-order/src
RUN mvn -f api-order/pom.xml package -DskipTests -q -B

FROM registry.suse.com/bci/openjdk:21

WORKDIR /app

COPY --from=builder /build/api-order/target/*.jar app.jar

RUN useradd -r -u 1001 -g root appuser && \
    mkdir -p /app/config && \
    chown -R appuser:root /app

USER appuser

EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseZGC -XX:+ZGenerational"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar --spring.config.additional-location=optional:file:/app/config/"]
