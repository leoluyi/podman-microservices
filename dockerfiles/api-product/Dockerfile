# API-Product Service Dockerfile
FROM registry.suse.com/bci/openjdk:17

LABEL description="Product API Service"
WORKDIR /app

RUN mkdir -p src/main/java/com/example/apiproduct

RUN cat > src/main/java/com/example/apiproduct/Application.java << 'EOF'
package com.example.apiproduct;

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
        response.put("service", "api-product");
        return response;
    }
    
    @GetMapping("/api/products")
    public Map<String, Object> getProducts(
        @RequestHeader(value = "X-Client-Name", required = false) String clientName) {
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Product API");
        response.put("client", clientName);
        response.put("products", Arrays.asList("product1", "product2"));
        return response;
    }
}
EOF

RUN cat > pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>api-product</artifactId>
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

CMD ["java", "-jar", "target/api-product-1.0.0.jar"]
