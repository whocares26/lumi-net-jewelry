#include "ReportController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ReportController::salesByCategory(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from=req->getParameter("from"); if(from.empty())from="2024-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    std::string cat =req->getParameter("category");
    std::string storeId=req->getParameter("store_id");
    app().getDbClient()->execSqlAsync(
        "WITH cat_sales AS ("
        "  SELECT p.product_category,"
        "         SUM(si.sale_item_quantity) AS total_qty,"
        "         SUM(p.product_price * si.sale_item_quantity) AS cat_revenue "
        "  FROM SALE s "
        "  JOIN SALE_ITEM si ON s.sale_id=si.sale_id "
        "  JOIN PRODUCT p ON si.product_article=p.product_article "
        "  WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "  AND ($3='' OR p.product_category=$3) "
        "  AND ($4='' OR s.store_id=$4::int) "
        "  GROUP BY p.product_category"
        "), total AS (SELECT SUM(cat_revenue) AS grand FROM cat_sales) "
        "SELECT cs.product_category, cs.total_qty, cs.cat_revenue,"
        "       ROUND((cs.cat_revenue::numeric/NULLIF(t.grand,0))*100,2) AS pct "
        "FROM cat_sales cs CROSS JOIN total t ORDER BY cs.cat_revenue DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["category"]=row["product_category"].as<std::string>();
                o["qty"]=static_cast<Json::Int64>(row["total_qty"].as<long long>());
                o["revenue"]=row["cat_revenue"].as<double>();
                o["pct"]=row["pct"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,cat,storeId);
}

void ReportController::stockStatus(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id"); if(storeId.empty())return cb(jsonErr("store_id required"));
    std::string thresh=req->getParameter("threshold"); if(thresh.empty())thresh="9999";
    app().getDbClient()->execSqlAsync(
        "SELECT p.product_article,p.product_name,p.product_category,p.product_price,st.stock_quantity "
        "FROM STOCK st JOIN PRODUCT p ON st.product_article=p.product_article "
        "WHERE st.store_id=$1::int AND st.stock_quantity<=$2::int "
        "ORDER BY st.stock_quantity ASC,p.product_name",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["article"]=row["product_article"].as<int>();
                o["name"]=row["product_name"].as<std::string>();
                o["category"]=row["product_category"].as<std::string>();
                o["price"]=row["product_price"].as<int>();
                o["qty"]=row["stock_quantity"].as<int>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,thresh);
}

void ReportController::ordersBySupplier(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string suppId=req->getParameter("supplier_id");
    std::string status=req->getParameter("status");
    std::string from=req->getParameter("from"); if(from.empty())from="2000-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    app().getDbClient()->execSqlAsync(
        "SELECT o.order_id,o.order_date,o.order_status,o.order_total,"
        "sp.supplier_name,s.store_address,m.manager_fio "
        "FROM \"ORDER\" o "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN STORE s ON o.store_id=s.store_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils "
        "WHERE ($1='' OR o.supplier_id=$1::int) "
        "AND ($2='' OR o.order_status=$2) "
        "AND o.order_date BETWEEN $3::date AND $4::date "
        "ORDER BY o.order_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["order_id"].as<int>();
                o["date"]=row["order_date"].as<std::string>();
                o["status"]=row["order_status"].as<std::string>();
                o["total"]=static_cast<Json::Int64>(row["order_total"].as<long long>());
                o["supplier"]=row["supplier_name"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["manager"]=row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        suppId,status,from,to);
}

void ReportController::revenueByStore(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from=req->getParameter("from"); if(from.empty())from="2024-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    std::string payment=req->getParameter("payment");
    app().getDbClient()->execSqlAsync(
        "SELECT st.store_id,st.store_address,"
        "SUM(s.sale_total) AS total_revenue,"
        "COUNT(*) AS tx_count,"
        "ROUND(AVG(s.sale_total)::numeric,2) AS avg_check "
        "FROM SALE s JOIN STORE st ON s.store_id=st.store_id "
        "WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "AND ($3='' OR s.sale_payment_method=$3) "
        "GROUP BY st.store_id,st.store_address ORDER BY total_revenue DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["store_id"]=row["store_id"].as<int>();
                o["store"]=row["store_address"].as<std::string>();
                o["revenue"]=row["total_revenue"].as<double>();
                o["tx_count"]=static_cast<Json::Int64>(row["tx_count"].as<long long>());
                o["avg_check"]=row["avg_check"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,payment);
}

void ReportController::topCustomers(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from=req->getParameter("from"); if(from.empty())from="2024-01-01";
    std::string to  =req->getParameter("to");   if(to.empty())  to  ="2099-12-31";
    std::string lim =req->getParameter("limit"); if(lim.empty())lim="10";
    app().getDbClient()->execSqlAsync(
        "SELECT c.client_fio,c.client_phone,"
        "COUNT(s.sale_id) AS purchase_count,"
        "SUM(s.sale_total) AS total_amount,"
        "ROUND(AVG(s.sale_total)::numeric,2) AS avg_check "
        "FROM CLIENT c JOIN SALE s ON c.client_id=s.client_id "
        "WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "GROUP BY c.client_id,c.client_fio,c.client_phone "
        "ORDER BY total_amount DESC LIMIT $3::int",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["fio"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["phone"]=row["client_phone"].as<std::string>();
                o["count"]=static_cast<Json::Int64>(row["purchase_count"].as<long long>());
                o["total"]=row["total_amount"].as<double>();
                o["avg"]=row["avg_check"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,lim);
}
