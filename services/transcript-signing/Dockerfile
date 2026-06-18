FROM eclipse-temurin:21-jre-alpine
RUN apk add --no-cache curl
WORKDIR /app
COPY app.jar app.jar
EXPOSE 8088
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD curl -sf http://localhost:8088/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
