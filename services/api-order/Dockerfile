FROM maven:3.9-eclipse-temurin-21-alpine AS builder
WORKDIR /build
COPY pom.xml ./pom.xml
RUN mvn -N install -q -B
COPY api-order/pom.xml ./api-order/pom.xml
RUN mvn -f api-order/pom.xml dependency:go-offline -q -B
COPY api-order/src ./api-order/src
RUN mvn -f api-order/pom.xml package -DskipTests -q -B

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=builder /build/api-order/target/*.jar app.jar
RUN mkdir -p /app/config && chown -R app:app /app
USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-XX:MaxRAMPercentage=75.0", \
    "-jar", "app.jar", \
    "--spring.config.additional-location=optional:file:/app/config/"]
