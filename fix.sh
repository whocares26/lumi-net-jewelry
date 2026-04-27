#!/bin/bash
# ================================================================
# lumi-net — патч ошибок компиляции
# Запуск: chmod +x fix.sh && ./fix.sh
# ================================================================
set -e
GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓${NC} $1"; }
hdr() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

PROJ="$(cd "$(dirname "$0")" && pwd)"
CTRL="$PROJ/backend/src/controllers"

hdr "Патч 1: StoreController.cc — auto& row → auto row"
cat > "$CTRL/StoreController.cc" << 'EOF'
#include "StoreController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void StoreController::getAll(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone,m.manager_fio "
        "FROM STORE s LEFT JOIN MANAGER m ON s.manager_snils=m.manager_snils ORDER BY s.store_id",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["store_id"].as<int>();
                o["address"]=row["store_address"].as<std::string>();
                o["phone"]=row["store_phone"].as<std::string>();
                o["manager"]=row["manager_fio"].isNull()?"":row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}
void StoreController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone,s.manager_snils,m.manager_fio "
        "FROM STORE s LEFT JOIN MANAGER m ON s.manager_snils=m.manager_snils WHERE s.store_id=$1",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Магазин не найден",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["id"]=row["store_id"].as<int>();
            o["address"]=row["store_address"].as<std::string>();
            o["phone"]=row["store_phone"].as<std::string>();
            o["manager"]=row["manager_fio"].isNull()?"":row["manager_fio"].as<std::string>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
void StoreController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string addr=(*b)["address"].asString(),phone=(*b)["phone"].asString();
    std::string msnils=(*b).get("manager_snils","").asString();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO STORE(store_address,store_phone,manager_snils) VALUES($1,$2,NULLIF($3,'')) RETURNING store_id",
        [cb](const orm::Result& r){Json::Value o;o["id"]=r[0]["store_id"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},addr,phone,msnils);
}
void StoreController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string addr=(*b)["address"].asString(),phone=(*b)["phone"].asString();
    std::string msnils=(*b).get("manager_snils","").asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE STORE SET store_address=$1,store_phone=$2,manager_snils=NULLIF($3,'') WHERE store_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},addr,phone,msnils,id);
}
void StoreController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM STORE WHERE store_id=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
EOF
ok "StoreController.cc"

hdr "Патч 2: ClientController.cc — auto& row → auto row"
cat > "$CTRL/ClientController.cc" << 'EOF'
#include "ClientController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ClientController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string srch=req->getParameter("search");
    app().getDbClient()->execSqlAsync(
        "SELECT client_id,client_fio,client_phone,client_email FROM CLIENT "
        "WHERE $1='' OR lower(client_fio) LIKE lower('%'||$1||'%') OR client_phone LIKE '%'||$1||'%' "
        "ORDER BY client_fio",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["client_id"].as<int>();
                o["fio"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["phone"]=row["client_phone"].as<std::string>();
                o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},srch);
}
void ClientController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT c.*,COUNT(s.sale_id) AS purchase_count,COALESCE(SUM(s.sale_total),0) AS total_spent "
        "FROM CLIENT c LEFT JOIN SALE s ON c.client_id=s.client_id WHERE c.client_id=$1 GROUP BY c.client_id",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Клиент не найден",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["id"]=row["client_id"].as<int>();
            o["fio"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
            o["phone"]=row["client_phone"].as<std::string>();
            o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
            o["purchase_count"]=row["purchase_count"].as<int>();
            o["total_spent"]=row["total_spent"].as<double>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
void ClientController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string fio=(*b)["fio"].asString(),phone=(*b)["phone"].asString(),email=(*b).get("email","").asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE CLIENT SET client_fio=$1,client_phone=$2,client_email=NULLIF($3,'') WHERE client_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},fio,phone,email,id);
}
EOF
ok "ClientController.cc"

hdr "Патч 3: SaleController.cc — auto& row → auto row"
cat > "$CTRL/SaleController.cc" << 'EOF'
#include "SaleController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void SaleController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id");
    std::string from=req->getParameter("from");
    std::string to=req->getParameter("to");
    app().getDbClient()->execSqlAsync(
        "SELECT s.sale_id,s.sale_date,s.sale_total,s.sale_payment_method,"
        "c.client_fio,c.client_phone,st.store_address,ca.cashier_fio "
        "FROM SALE s "
        "JOIN CLIENT c ON s.client_id=c.client_id "
        "JOIN STORE st ON s.store_id=st.store_id "
        "JOIN CASHIER ca ON s.cashier_snils=ca.cashier_snils "
        "WHERE ($1='' OR s.store_id=$1::int) "
        "AND ($2='' OR s.sale_date>=$2::date) "
        "AND ($3='' OR s.sale_date<=$3::date) "
        "ORDER BY s.sale_date DESC LIMIT 200",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["sale_id"].as<int>();
                o["date"]=row["sale_date"].as<std::string>();
                o["total"]=row["sale_total"].as<double>();
                o["payment"]=row["sale_payment_method"].as<std::string>();
                o["client"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["client_phone"]=row["client_phone"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["cashier"]=row["cashier_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,from,to);
}

void SaleController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT s.*,c.client_fio,c.client_phone,st.store_address,ca.cashier_fio "
        "FROM SALE s JOIN CLIENT c ON s.client_id=c.client_id "
        "JOIN STORE st ON s.store_id=st.store_id "
        "JOIN CASHIER ca ON s.cashier_snils=ca.cashier_snils WHERE s.sale_id=$1",
        [cb,id](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Продажа не найдена",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["id"]=row["sale_id"].as<int>();
            o["date"]=row["sale_date"].as<std::string>();
            o["total"]=row["sale_total"].as<double>();
            o["payment"]=row["sale_payment_method"].as<std::string>();
            o["client"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
            o["store"]=row["store_address"].as<std::string>();
            o["cashier"]=row["cashier_fio"].as<std::string>();
            app().getDbClient()->execSqlAsync(
                "SELECT si.sale_item_quantity,p.product_name,p.product_article,p.product_price "
                "FROM SALE_ITEM si JOIN PRODUCT p ON si.product_article=p.product_article WHERE si.sale_id=$1",
                [cb,o](const orm::Result& ri) mutable {
                    Json::Value items(Json::arrayValue);
                    for(const auto& row2:ri){Json::Value itm;
                        itm["name"]=row2["product_name"].as<std::string>();
                        itm["article"]=row2["product_article"].as<int>();
                        itm["price"]=row2["product_price"].as<int>();
                        itm["qty"]=row2["sale_item_quantity"].as<int>();
                        items.append(itm);}
                    o["items"]=items;
                    auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
                [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void SaleController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int clientId=(*b)["client_id"].asInt();
    std::string cashierSnils=(*b)["cashier_snils"].asString();
    int storeId=(*b)["store_id"].asInt();
    std::string payment=(*b)["payment_method"].asString();
    Json::Value items=(*b)["items"];
    if(!items.isArray()||items.empty())return cb(jsonErr("items обязателен и не должен быть пустым"));
    double total=0;
    for(const auto& itm:items) total+=itm["price"].asDouble()*itm["qty"].asInt();
    auto db=app().getDbClient();
    db->execSqlAsync(
        "INSERT INTO SALE(client_id,cashier_snils,store_id,sale_total,sale_payment_method,sale_date) "
        "VALUES($1,$2,$3,$4,$5,CURRENT_DATE) RETURNING sale_id",
        [cb,items,db](const orm::Result& r){
            int saleId=r[0]["sale_id"].as<int>();
            int itemIdx=1;
            for(const auto& itm:items){
                int art=itm["article"].asInt();int qty=itm["qty"].asInt();
                db->execSqlAsync(
                    "INSERT INTO SALE_ITEM(sale_id,sale_item_id,product_article,sale_item_quantity) VALUES($1,$2,$3,$4)",
                    [](const orm::Result&){},[](const orm::DrogonDbException&){},saleId,itemIdx++,art,qty);}
            Json::Value o;o["id"]=saleId;o["ok"]=true;
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        clientId,cashierSnils,storeId,total,payment);
}

void SaleController::clientSales(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int clientId){
    std::string from=req->getParameter("from");
    std::string to=req->getParameter("to");
    app().getDbClient()->execSqlAsync(
        "SELECT s.sale_id,s.sale_date,s.sale_total,s.sale_payment_method,st.store_address,"
        "array_agg(p.product_name) AS products "
        "FROM SALE s JOIN STORE st ON s.store_id=st.store_id "
        "JOIN SALE_ITEM si ON s.sale_id=si.sale_id "
        "JOIN PRODUCT p ON si.product_article=p.product_article "
        "WHERE s.client_id=$1 AND ($2='' OR s.sale_date>=$2::date) AND ($3='' OR s.sale_date<=$3::date) "
        "GROUP BY s.sale_id,st.store_address ORDER BY s.sale_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["sale_id"].as<int>();
                o["date"]=row["sale_date"].as<std::string>();
                o["total"]=row["sale_total"].as<double>();
                o["payment"]=row["sale_payment_method"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["products"]=row["products"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        clientId,from,to);
}
EOF
ok "SaleController.cc"

hdr "Патч 4: OrderController.cc — auto& row + long long cast"
cat > "$CTRL/OrderController.cc" << 'EOF'
#include "OrderController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void OrderController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id");
    std::string status=req->getParameter("status");
    std::string suppId=req->getParameter("supplier_id");
    app().getDbClient()->execSqlAsync(
        "SELECT o.order_id,o.order_date,o.order_status,o.order_total,"
        "s.store_address,sp.supplier_name,m.manager_fio "
        "FROM \"ORDER\" o "
        "JOIN STORE s ON o.store_id=s.store_id "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils "
        "WHERE ($1='' OR o.store_id=$1::int) "
        "AND ($2='' OR o.order_status=$2) "
        "AND ($3='' OR o.supplier_id=$3::int) "
        "ORDER BY o.order_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["order_id"].as<int>();
                o["date"]=row["order_date"].as<std::string>();
                o["status"]=row["order_status"].as<std::string>();
                o["total"]=static_cast<Json::Int64>(row["order_total"].as<long long>());
                o["store"]=row["store_address"].as<std::string>();
                o["supplier"]=row["supplier_name"].as<std::string>();
                o["manager"]=row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,status,suppId);
}

void OrderController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT o.*,s.store_address,sp.supplier_name,m.manager_fio "
        "FROM \"ORDER\" o JOIN STORE s ON o.store_id=s.store_id "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils WHERE o.order_id=$1",
        [cb,id](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Заказ не найден",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["id"]=row["order_id"].as<int>();
            o["date"]=row["order_date"].as<std::string>();
            o["status"]=row["order_status"].as<std::string>();
            o["total"]=static_cast<Json::Int64>(row["order_total"].as<long long>());
            o["store"]=row["store_address"].as<std::string>();
            o["supplier"]=row["supplier_name"].as<std::string>();
            o["manager"]=row["manager_fio"].as<std::string>();
            app().getDbClient()->execSqlAsync(
                "SELECT oi.order_item_quantity,p.product_name,p.product_article,p.product_price "
                "FROM ORDER_ITEM oi JOIN PRODUCT p ON oi.product_article=p.product_article WHERE oi.order_id=$1",
                [cb,o](const orm::Result& ri) mutable {
                    Json::Value items(Json::arrayValue);
                    for(const auto& row2:ri){Json::Value itm;
                        itm["name"]=row2["product_name"].as<std::string>();
                        itm["article"]=row2["product_article"].as<int>();
                        itm["price"]=row2["product_price"].as<int>();
                        itm["qty"]=row2["order_item_quantity"].as<int>();
                        items.append(itm);}
                    o["items"]=items;
                    auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
                [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void OrderController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int storeId=(*b)["store_id"].asInt();
    int suppId=(*b)["supplier_id"].asInt();
    Json::Value items=(*b)["items"];
    if(!items.isArray()||items.empty())return cb(jsonErr("items required"));
    std::string arts="ARRAY[",qtys="ARRAY[";
    for(unsigned i=0;i<items.size();i++){
        if(i)arts+=",",qtys+=",";
        arts+=std::to_string(items[i]["article"].asInt());
        qtys+=std::to_string(items[i]["qty"].asInt());}
    arts+="]::INT[]";qtys+="]::INT[]";
    std::string sql="CALL create_supplier_order("+std::to_string(storeId)+","+
                    std::to_string(suppId)+","+arts+","+qtys+",NULL)";
    app().getDbClient()->execSqlAsync(sql,
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->setStatusCode(k201Created);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}

void OrderController::updateStatus(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string status=(*b)["status"].asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE \"ORDER\" SET order_status=$1 WHERE order_id=$2",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},status,id);
}
EOF
ok "OrderController.cc"

hdr "Патч 5: ReportController.cc — long long → Json::Int64"
cat > "$CTRL/ReportController.cc" << 'EOF'
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
EOF
ok "ReportController.cc"

hdr "Патч 6: ProductController.cc — columnIndex + auto& row"
cat > "$CTRL/ProductController.cc" << 'EOF'
#include "ProductController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ProductController::getAll(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string cat  = req->getParameter("category");
    std::string srch = req->getParameter("search");
    std::string storeId = req->getParameter("store_id");
    auto db=app().getDbClient();
    if(!storeId.empty()){
        db->execSqlAsync(
            "SELECT p.product_article,p.product_name,p.product_category,p.product_price,"
            "COALESCE(s.stock_quantity,0) AS stock_quantity "
            "FROM PRODUCT p LEFT JOIN STOCK s ON p.product_article=s.product_article AND s.store_id=$1::int "
            "WHERE ($2='' OR p.product_category=$2) AND ($3='' OR lower(p.product_name) LIKE lower('%'||$3||'%')) "
            "ORDER BY p.product_category,p.product_name",
            [cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(const auto& row:r){Json::Value o;
                    o["article"]=row["product_article"].as<int>();
                    o["name"]=row["product_name"].as<std::string>();
                    o["category"]=row["product_category"].as<std::string>();
                    o["price"]=row["product_price"].as<int>();
                    o["stock_quantity"]=row["stock_quantity"].as<int>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
            [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            storeId,cat,srch);
    } else {
        db->execSqlAsync(
            "SELECT product_article,product_name,product_category,product_price FROM PRODUCT "
            "WHERE ($1='' OR product_category=$1) AND ($2='' OR lower(product_name) LIKE lower('%'||$2||'%')) "
            "ORDER BY product_category,product_name",
            [cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(const auto& row:r){Json::Value o;
                    o["article"]=row["product_article"].as<int>();
                    o["name"]=row["product_name"].as<std::string>();
                    o["category"]=row["product_category"].as<std::string>();
                    o["price"]=row["product_price"].as<int>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
            [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            cat,srch);
    }
}

void ProductController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    app().getDbClient()->execSqlAsync(
        "SELECT * FROM PRODUCT WHERE product_article=$1",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Товар не найден",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["article"]=row["product_article"].as<int>();
            o["name"]=row["product_name"].as<std::string>();
            o["category"]=row["product_category"].as<std::string>();
            o["price"]=row["product_price"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},art);
}

void ProductController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("Требуется JSON"));
    int art=(*b)["article"].asInt();
    std::string name=(*b)["name"].asString(),cat=(*b)["category"].asString();
    int price=(*b)["price"].asInt();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO PRODUCT(product_article,product_name,product_category,product_price) VALUES($1,$2,$3,$4)",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->setStatusCode(k201Created);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        art,name,cat,price);
}

void ProductController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("Требуется JSON"));
    std::string name=(*b)["name"].asString(),cat=(*b)["category"].asString();
    int price=(*b)["price"].asInt();
    app().getDbClient()->execSqlAsync(
        "UPDATE PRODUCT SET product_name=$1,product_category=$2,product_price=$3 WHERE product_article=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        name,cat,price,art);
}

void ProductController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    app().getDbClient()->execSqlAsync("DELETE FROM PRODUCT WHERE product_article=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},art);
}
EOF
ok "ProductController.cc"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Все патчи применены! Теперь запустите:${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  docker compose up --build"
echo ""
