package com.example.auth.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.List;
import java.util.Map;

@Service
public class JwtService {
    private final SecretKey signingKey;
    private final long accessExpirationMs;
    private final long refreshExpirationMs;

    public JwtService(@Value("${jwt.signing-key}") String secret,
                      @Value("${jwt.expiration-ms}") long accessMs,
                      @Value("${jwt.refresh-expiration-ms}") long refreshMs) {
        this.signingKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.accessExpirationMs = accessMs;
        this.refreshExpirationMs = refreshMs;
    }

    public String generateAccessToken(String username, List<String> roles, List<String> permissions) {
        return Jwts.builder()
            .subject(username)
            .claims(Map.of("roles", roles, "permissions", permissions, "type", "access"))
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + accessExpirationMs))
            .signWith(signingKey).compact();
    }

    public String generateRefreshToken(String username) {
        return Jwts.builder()
            .subject(username).claims(Map.of("type", "refresh"))
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + refreshExpirationMs))
            .signWith(signingKey).compact();
    }

    public Claims parseToken(String token) {
        return Jwts.parser().verifyWith(signingKey).build()
            .parseSignedClaims(token).getPayload();
    }

    public boolean isValid(String token) {
        try { parseToken(token); return true; }
        catch (Exception e) { return false; }
    }

    public String getUsername(String token) { return parseToken(token).getSubject(); }

    public long getAccessExpirationMs() { return accessExpirationMs; }
}
