# Stage 1: Build
FROM drogonframework/drogon:latest AS builder
WORKDIR /build
COPY CMakeLists.txt .
COPY src/ src/
RUN cmake -B cmake-build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build cmake-build --target lumi_backend -j$(nproc)

# Stage 2: Runtime (same image — all libs present)
FROM drogonframework/drogon:latest
WORKDIR /app
COPY --from=builder /build/cmake-build/lumi_backend .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh
EXPOSE 8080
ENTRYPOINT ["./entrypoint.sh"]
