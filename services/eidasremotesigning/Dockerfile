FROM eclipse-temurin:17-jre-alpine
RUN apk add --no-cache curl
WORKDIR /app
RUN mkdir -p /app/keystores
COPY app.jar app.jar
EXPOSE 9000
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
    CMD curl -sf http://localhost:9000/actuator/health || exit 1
ENTRYPOINT ["java", "-jar", "app.jar"]
