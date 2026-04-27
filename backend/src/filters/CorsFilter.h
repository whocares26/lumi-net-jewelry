#pragma once
#include <drogon/HttpFilter.h>

class CorsFilter : public drogon::HttpFilter<CorsFilter> {
public:
    void doFilter(const drogon::HttpRequestPtr& req,
                  drogon::FilterCallback&&      stop,
                  drogon::FilterChainCallback&& next) override;
};
