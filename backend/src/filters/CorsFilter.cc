#include "CorsFilter.h"

void CorsFilter::doFilter(const drogon::HttpRequestPtr& req,
                           drogon::FilterCallback&&      stop,
                           drogon::FilterChainCallback&& next) {
    if (req->method() == drogon::Options) {
        auto resp = drogon::HttpResponse::newHttpResponse();
        resp->addHeader("Access-Control-Allow-Origin",  "*");
        resp->addHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
        resp->addHeader("Access-Control-Allow-Headers", "Content-Type,Authorization");
        resp->setStatusCode(drogon::k204NoContent);
        stop(resp);
        return;
    }
    next();
}
