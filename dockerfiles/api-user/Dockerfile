# API-User Service Dockerfile
# Base: SUSE BCI OpenJDK 17

FROM registry.suse.com/bci/openjdk:17

LABEL maintainer="your-team@example.com"
LABEL description="User API Service"
LABEL version="1.0.0"

# 工作目錄
WORKDIR /app

# 複製應用程式
# 方式一：複製已編譯的 JAR
# COPY target/api-user-*.jar app.jar

# 方式二：使用範例應用（示範用）
# 這裡建立一個簡單的 Spring Boot 應用程式框架
RUN mkdir -p src/main/java/com/example/apiuser

# 建立簡單的 Spring Boot 主程式（示範）
RUN cat > src/main/java/com/example/apiuser/Application.java << 'EOF'
package com.example.apiuser;

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
        response.put("service", "api-user");
        return response;
    }
    
    @GetMapping("/api/users")
    public Map<String, Object> getUsers(
        @RequestHeader(value = "X-User-ID", required = false) String userId) {
        Map<String, Object> response = new HashMap<>();
        response.put("message", "User API");
        response.put("authenticated_user", userId);
        response.put("users", Arrays.asList("user1", "user2", "user3"));
        return response;
    }
}
EOF

# 建立 pom.xml（示範）
RUN cat > pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>api-user</artifactId>
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

# 安裝 Maven（SUSE BCI 需要手動安裝）
USER root
RUN zypper --non-interactive install maven

# 編譯應用程式
RUN mvn clean package -DskipTests

# 暴露端口
EXPOSE 8080

# 健康檢查
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# 執行應用程式
CMD ["java", "-jar", "target/api-user-1.0.0.jar"]
