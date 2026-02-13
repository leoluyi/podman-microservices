# API-Order Service Dockerfile
# Base: SUSE BCI OpenJDK 17

FROM registry.suse.com/bci/openjdk:17

LABEL maintainer="your-team@example.com"
LABEL description="Order API Service"

WORKDIR /app

# 建立簡單的 Spring Boot 應用
RUN mkdir -p src/main/java/com/example/apiorder

RUN cat > src/main/java/com/example/apiorder/Application.java << 'EOF'
package com.example.apiorder;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@SpringBootApplication
@RestController
public class Application {
    
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
    
    @GetMapping("/health")
    public Map<String, String> health() {
        Map<String, String> response = new HashMap<>();
        response.put("status", "healthy");
        response.put("service", "api-order");
        return response;
    }
    
    @GetMapping("/api/orders")
    public Map<String, Object> getOrders(
        @RequestHeader(value = "X-User-ID", required = false) String userId,
        @RequestHeader(value = "X-Client-Name", required = false) String clientName) {
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Order API");
        response.put("authenticated_user", userId);
        response.put("client", clientName);
        response.put("orders", Arrays.asList("order1", "order2"));
        return response;
    }
}
EOF

RUN cat > pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>api-order</artifactId>
    <version>1.0.0</version>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
    </parent>
    <properties>
        <java.version>17</java.version>
    </properties>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
    </dependencies>
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
EOF

USER root
RUN zypper --non-interactive install maven curl
RUN mvn clean package -DskipTests

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["java", "-jar", "target/api-order-1.0.0.jar"]
