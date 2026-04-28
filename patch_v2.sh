#!/bin/bash
# ================================================================
# lumi-net patch v2 — role-specific UX + business logic
# Запуск: chmod +x patch_v2.sh && ./patch_v2.sh
# ================================================================
set -e
PROJ="$(cd "$(dirname "$0")" && pwd)"
CTRL="$PROJ/backend/src/controllers"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓${NC} $1"; }
hdr() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

# ═══════════════════════════════════════════════════════════════
# 1. InfoController — /api/cashiers/:snils/store
#                     /api/managers/:snils/store
#                     /api/products/:article/stock-all
# ═══════════════════════════════════════════════════════════════
hdr "1. InfoController"
cat > "$CTRL/InfoController.h" << 'EOF'
#pragma once
#include <drogon/HttpController.h>
class InfoController : public drogon::HttpController<InfoController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(InfoController::cashierStore,  "/api/cashiers/{1}/store",       drogon::Get);
    ADD_METHOD_TO(InfoController::managerStore,  "/api/managers/{1}/store",       drogon::Get);
    ADD_METHOD_TO(InfoController::productStocks, "/api/products/{1}/stock-all",   drogon::Get);
    METHOD_LIST_END
    void cashierStore (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,std::string);
    void managerStore (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,std::string);
    void productStocks(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
EOF

cat > "$CTRL/InfoController.cc" << 'EOF'
#include "InfoController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

// GET /api/cashiers/:snils/store
void InfoController::cashierStore(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb, std::string snils){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone "
        "FROM STORE s WHERE s.manager_snils=("
        "  SELECT manager_snils FROM CASHIER WHERE cashier_snils=$1)",
        [cb](const orm::Result& r){
            if(r.empty()) return cb(jsonErr("Магазин кассира не найден",k404NotFound));
            const auto row=r[0]; Json::Value o;
            o["id"]      = row["store_id"].as<int>();
            o["address"] = row["store_address"].as<std::string>();
            o["phone"]   = row["store_phone"].as<std::string>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        snils);
}

// GET /api/managers/:snils/store
void InfoController::managerStore(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb, std::string snils){
    app().getDbClient()->execSqlAsync(
        "SELECT store_id,store_address,store_phone FROM STORE WHERE manager_snils=$1",
        [cb](const orm::Result& r){
            if(r.empty()) return cb(jsonErr("Магазин менеджера не найден",k404NotFound));
            const auto row=r[0]; Json::Value o;
            o["id"]      = row["store_id"].as<int>();
            o["address"] = row["store_address"].as<std::string>();
            o["phone"]   = row["store_phone"].as<std::string>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        snils);
}

// GET /api/products/:article/stock-all — остатки во всех магазинах
void InfoController::productStocks(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb, int article){
    app().getDbClient()->execSqlAsync(
        "SELECT st.stock_quantity,s.store_id,s.store_address "
        "FROM STOCK st JOIN STORE s ON st.store_id=s.store_id "
        "WHERE st.product_article=$1 ORDER BY st.stock_quantity DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["qty"]     = row["stock_quantity"].as<int>();
                o["store_id"]= row["store_id"].as<int>();
                o["address"] = row["store_address"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        article);
}
EOF
ok "InfoController.h + .cc"

# ═══════════════════════════════════════════════════════════════
# 2. ReviewController — добавить адрес магазина к отзыву
# ═══════════════════════════════════════════════════════════════
hdr "2. ReviewController — store address"
cat > "$CTRL/ReviewController.cc" << 'EOF'
#include "ReviewController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ReviewController::getAll(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        "SELECT r.review_id,r.review_rating,r.review_comment,r.review_date,c.client_fio,"
        "(SELECT st.store_address FROM SALE sa "
        " JOIN STORE st ON sa.store_id=st.store_id "
        " WHERE sa.client_id=r.client_id "
        " ORDER BY sa.sale_date DESC LIMIT 1) AS store_address "
        "FROM REVIEW r JOIN CLIENT c ON r.client_id=c.client_id "
        "ORDER BY r.review_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]      = row["review_id"].as<int>();
                o["rating"]  = row["review_rating"].as<int>();
                o["comment"] = row["review_comment"].isNull()?"":row["review_comment"].as<std::string>();
                o["date"]    = row["review_date"].isNull()?"":row["review_date"].as<std::string>();
                o["client"]  = row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["store"]   = row["store_address"].isNull()?"Магазин не указан":row["store_address"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}

void ReviewController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int clientId=(*b)["client_id"].asInt();
    int rating=(*b)["rating"].asInt();
    std::string comment=(*b).get("comment","").asString();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO REVIEW(client_id,review_rating,review_comment,review_date) "
        "VALUES($1,$2,$3,CURRENT_DATE) RETURNING review_id",
        [cb](const orm::Result& r){Json::Value o;o["id"]=r[0]["review_id"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        clientId,rating,comment);
}

void ReviewController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM REVIEW WHERE review_id=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
EOF
ok "ReviewController.cc"

# ═══════════════════════════════════════════════════════════════
# 3. ProductController — авто-артикул через sequence
# ═══════════════════════════════════════════════════════════════
hdr "3. ProductController — auto article"
cat > "$CTRL/ProductController.cc" << 'EOF'
#include "ProductController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ProductController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string cat=req->getParameter("category");
    std::string srch=req->getParameter("search");
    std::string storeId=req->getParameter("store_id");
    auto db=app().getDbClient();
    if(!storeId.empty()){
        db->execSqlAsync(
            "SELECT p.product_article,p.product_name,p.product_category,p.product_price,"
            "COALESCE(s.stock_quantity,0) AS stock_quantity "
            "FROM PRODUCT p LEFT JOIN STOCK s ON p.product_article=s.product_article AND s.store_id=$1::int "
            "WHERE ($2='' OR p.product_category=$2) "
            "AND ($3='' OR lower(p.product_name) LIKE lower('%'||$3||'%') "
            "     OR CAST(p.product_article AS TEXT) LIKE '%'||$3||'%') "
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
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
            [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            storeId,cat,srch);
    } else {
        db->execSqlAsync(
            "SELECT product_article,product_name,product_category,product_price FROM PRODUCT "
            "WHERE ($1='' OR product_category=$1) "
            "AND ($2='' OR lower(product_name) LIKE lower('%'||$2||'%') "
            "     OR CAST(product_article AS TEXT) LIKE '%'||$2||'%') "
            "ORDER BY product_category,product_name",
            [cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(const auto& row:r){Json::Value o;
                    o["article"]=row["product_article"].as<int>();
                    o["name"]=row["product_name"].as<std::string>();
                    o["category"]=row["product_category"].as<std::string>();
                    o["price"]=row["product_price"].as<int>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
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
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},art);
}

// Создание — артикул определяется автоматически через sequence
void ProductController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("Требуется JSON"));
    std::string name=(*b)["name"].asString();
    std::string cat=(*b)["category"].asString();
    int price=(*b)["price"].asInt();
    if(name.empty()||cat.empty()||price<=0)return cb(jsonErr("Заполните все поля"));
    app().getDbClient()->execSqlAsync(
        "INSERT INTO PRODUCT(product_article,product_name,product_category,product_price) "
        "VALUES(nextval('product_article_seq'),$1,$2,$3) RETURNING product_article",
        [cb](const orm::Result& r){
            Json::Value o;o["article"]=r[0]["product_article"].as<int>();o["ok"]=true;
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        name,cat,price);
}

void ProductController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("Требуется JSON"));
    std::string name=(*b)["name"].asString();
    std::string cat=(*b)["category"].asString();
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

# ═══════════════════════════════════════════════════════════════
# 4. CMakeLists — добавить InfoController
# ═══════════════════════════════════════════════════════════════
hdr "4. CMakeLists.txt"
cat > "$PROJ/backend/CMakeLists.txt" << 'EOF'
cmake_minimum_required(VERSION 3.15)
project(lumi_backend CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Drogon CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)

set(SOURCES
    src/main.cc
    src/utils/JwtUtils.cc
    src/filters/CorsFilter.cc
    src/controllers/AuthController.cc
    src/controllers/ProductController.cc
    src/controllers/StoreController.cc
    src/controllers/SaleController.cc
    src/controllers/OrderController.cc
    src/controllers/StockController.cc
    src/controllers/ReportController.cc
    src/controllers/ClientController.cc
    src/controllers/SupplierController.cc
    src/controllers/ReviewController.cc
    src/controllers/InfoController.cc
)

add_executable(lumi_backend ${SOURCES})
target_link_libraries(lumi_backend PRIVATE Drogon::Drogon OpenSSL::Crypto)
target_include_directories(lumi_backend PRIVATE src)
EOF
ok "CMakeLists.txt"

# ═══════════════════════════════════════════════════════════════
# 5. seed.sql — sequence для product_article
# ═══════════════════════════════════════════════════════════════
hdr "5. seed.sql — product_article sequence"
# Append sequence creation before the INSERT INTO PRODUCT block
sed -i '/^-- ─── Products/i -- Auto-increment sequence for product_article\nCREATE SEQUENCE IF NOT EXISTS product_article_seq START 100021 OWNED BY PRODUCT.product_article;\nALTER TABLE PRODUCT ALTER COLUMN product_article SET DEFAULT nextval('"'"'product_article_seq'"'"');\n' \
    "$PROJ/database/seed.sql" 2>/dev/null || true

# Also append at end as fallback
cat >> "$PROJ/database/seed.sql" << 'EOF'

-- Sequence (idempotent fallback)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='product_article_seq') THEN
    CREATE SEQUENCE product_article_seq START 100021 OWNED BY PRODUCT.product_article;
    ALTER TABLE PRODUCT ALTER COLUMN product_article SET DEFAULT nextval('product_article_seq');
  END IF;
  PERFORM setval('product_article_seq', COALESCE((SELECT MAX(product_article) FROM PRODUCT),100020)+1);
END $$;
EOF
ok "seed.sql"


# ═══════════════════════════════════════════════════════════════
# 6. FRONTEND — полная замена app.js
# ═══════════════════════════════════════════════════════════════
hdr "6. Frontend app.js"
cat > "$PROJ/frontend/js/app.js" << 'JS_EOF'
'use strict';
// ── State ─────────────────────────────────────────────────────
let TOKEN=null,ROLE=null,REF=null,USER_ID=null;
let MY_STORE=null; // {id, address, phone} — для кассира и менеджера
const API='/api';
const PAGE_SIZE=20;

// ── API ───────────────────────────────────────────────────────
async function api(path,opts={}){
  const headers={'Content-Type':'application/json',...(TOKEN?{Authorization:'Bearer '+TOKEN}:{})};
  const r=await fetch(API+path,{headers,...opts});
  if(r.status===204)return{};
  const txt=await r.text();
  let data;try{data=JSON.parse(txt);}catch{data={raw:txt};}
  if(!r.ok)throw new Error(data.error||'Ошибка '+r.status);
  return data;
}
const get=(p,q={})=>api(p+(Object.keys(q).length?'?'+new URLSearchParams(q):''));
const post=(p,b)=>api(p,{method:'POST',body:JSON.stringify(b)});
const put=(p,b)=>api(p,{method:'PUT',body:JSON.stringify(b)});
const del=p=>api(p,{method:'DELETE'});

// ── Helpers ───────────────────────────────────────────────────
const esc=s=>String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const fmt=n=>new Intl.NumberFormat('ru-RU').format(n||0);
const fmtMoney=n=>(n||0).toLocaleString('ru-RU',{style:'currency',currency:'RUB',maximumFractionDigits:0});
const fmtDate=s=>s?new Date(s).toLocaleDateString('ru-RU'):'—';
function statusBadge(s){
  const m={Доставлен:'success',Принят:'success','В пути':'info','В обработке':'warning',
    Ожидается:'warning',ожидается:'warning',Отменен:'danger',Отменён:'danger'};
  return`<span class="badge badge-${m[s]||'gold'}">${esc(s)}</span>`;
}
function stars(n){return'★'.repeat(n)+'☆'.repeat(5-n);}
function paginate(arr,page,size){
  const total=Math.ceil(arr.length/size);
  return{items:arr.slice((page-1)*size,page*size),total,page};
}
function paginationHtml(p,total,cb){
  if(total<=1)return'';
  let h='<div class="pagination">';
  if(p>1)h+=`<button class="page-btn" onclick="${cb}(${p-1})">‹</button>`;
  for(let i=1;i<=total;i++)h+=`<button class="page-btn${i===p?' active':''}" onclick="${cb}(${i})">${i}</button>`;
  if(p<total)h+=`<button class="page-btn" onclick="${cb}(${p+1})">›</button>`;
  return h+'</div>';
}
function openModal(title,body,footer=''){
  document.getElementById('modal-title').textContent=title;
  document.getElementById('modal-body').innerHTML=body;
  document.getElementById('modal-footer').innerHTML=footer;
  document.getElementById('modal-overlay').classList.add('open');
}
function closeModal(){document.getElementById('modal-overlay').classList.remove('open');}
function closeModalIfBg(e){if(e.target===document.getElementById('modal-overlay'))closeModal();}
function showAlert(msg,type='ok',id='page-alert'){
  const el=document.getElementById(id);
  if(el){el.innerHTML=`<div class="alert alert-${type}">${esc(msg)}</div>`;
    setTimeout(()=>{el.innerHTML='';},4000);}
}
function setPage(html){document.getElementById('page').innerHTML=html;}

// ── Auth ──────────────────────────────────────────────────────
async function doLogin(){
  const u=document.getElementById('au-user').value.trim();
  const p=document.getElementById('au-pass').value;
  if(!u||!p)return showAuthErr('Заполните все поля');
  try{
    const d=await post('/auth/login',{username:u,password:p});
    TOKEN=d.token;ROLE=d.role;REF=d.ref;USER_ID=d.user_id;
    localStorage.setItem('lumi_token',TOKEN);
    localStorage.setItem('lumi_role',ROLE);
    localStorage.setItem('lumi_ref',REF||'');
    localStorage.setItem('lumi_uid',USER_ID);
    await bootApp();
  }catch(e){showAuthErr(e.message);}
}
async function doRegister(){
  const fio=document.getElementById('ru-fio').value.trim();
  const phone=document.getElementById('ru-phone').value.trim();
  const uname=document.getElementById('ru-user').value.trim();
  const pass=document.getElementById('ru-pass').value;
  const email=document.getElementById('ru-email').value.trim();
  if(!fio||!phone||!uname||!pass)return showAuthErr('Заполните обязательные поля');
  try{
    const d=await post('/auth/register',{fio,phone,username:uname,password:pass,email});
    TOKEN=d.token;ROLE=d.role;REF=String(d.client_id);USER_ID=d.user_id;
    localStorage.setItem('lumi_token',TOKEN);
    localStorage.setItem('lumi_role',ROLE);
    localStorage.setItem('lumi_ref',REF);
    localStorage.setItem('lumi_uid',USER_ID);
    await bootApp();
  }catch(e){showAuthErr(e.message);}
}
function showAuthErr(m){const el=document.getElementById('auth-err');el.innerHTML=`<div class="alert alert-err">${esc(m)}</div>`;}
function showRegForm(){document.getElementById('auth-login-form').style.display='none';document.getElementById('auth-reg-form').style.display='';}
function showLoginForm(){document.getElementById('auth-reg-form').style.display='none';document.getElementById('auth-login-form').style.display='';}
function logout(){TOKEN=ROLE=REF=USER_ID=MY_STORE=null;localStorage.clear();location.reload();}

// ── Boot ──────────────────────────────────────────────────────
async function bootApp(){
  document.getElementById('auth-screen').style.display='none';
  document.getElementById('app').style.display='flex';
  const roleLabels={ADMIN:'Администратор',MANAGER:'Менеджер',CASHIER:'Кассир',CLIENT:'Клиент'};
  document.getElementById('ua-role').textContent=roleLabels[ROLE]||ROLE;
  // Загружаем магазин для кассира/менеджера
  if(ROLE==='CASHIER'&&REF){
    try{MY_STORE=await get('/cashiers/'+encodeURIComponent(REF.trim())+'/store');}catch(e){console.warn('store:',e);}
  }
  if(ROLE==='MANAGER'&&REF){
    try{MY_STORE=await get('/managers/'+encodeURIComponent(REF.trim())+'/store');}catch(e){console.warn('store:',e);}
  }
  const storeLabel=MY_STORE?' — '+MY_STORE.address.split(',').slice(-1)[0].trim():'';
  document.getElementById('ua-name').textContent=
    ROLE==='CLIENT'?'Клиент #'+REF:
    ROLE==='CASHIER'?'Кассир'+storeLabel:
    ROLE==='MANAGER'?'Менеджер'+storeLabel:'Администратор';
  document.getElementById('ua-initials').textContent=(roleLabels[ROLE]||'?')[0];
  buildNav();
  // Клиент сразу в каталог, остальные — дашборд
  navigate(ROLE==='CLIENT'?'catalog':'dashboard');
}
function tryAutoLogin(){
  TOKEN=localStorage.getItem('lumi_token');
  ROLE=localStorage.getItem('lumi_role');
  REF=localStorage.getItem('lumi_ref');
  USER_ID=+localStorage.getItem('lumi_uid');
  if(TOKEN&&ROLE) bootApp();
}

// ── Navigation ────────────────────────────────────────────────
const PAGES={
  ADMIN:  [{id:'dashboard',icon:'◆',label:'Дашборд'},
            {sec:'Продажи'},{id:'sales',icon:'🛒',label:'Продажи'},{id:'clients',icon:'👤',label:'Клиенты'},
            {sec:'Каталог'},{id:'products',icon:'💎',label:'Товары'},{id:'stock',icon:'📦',label:'Остатки'},
            {sec:'Снабжение'},{id:'orders',icon:'📋',label:'Заказы'},{id:'suppliers',icon:'🏭',label:'Поставщики'},
            {sec:'Управление'},{id:'stores',icon:'🏪',label:'Магазины'},{id:'reviews',icon:'⭐',label:'Отзывы'},
            {sec:'Аналитика'},{id:'reports',icon:'📊',label:'Отчёты'}],
  MANAGER:[{id:'dashboard',icon:'◆',label:'Дашборд'},
            {sec:'Продажи'},{id:'sales',icon:'🛒',label:'Продажи'},
            {sec:'Каталог'},{id:'products',icon:'💎',label:'Товары'},{id:'stock',icon:'📦',label:'Остатки'},
            {sec:'Снабжение'},{id:'orders',icon:'📋',label:'Заказы'},
            {sec:'Клиенты'},{id:'clients',icon:'👤',label:'Клиенты магазина'},
            {sec:'Аналитика'},{id:'reports',icon:'📊',label:'Отчёты'}],
  CASHIER:[{id:'dashboard',icon:'◆',label:'Дашборд'},
            {id:'sale_new',icon:'🛒',label:'Оформить продажу'},
            {id:'sales',icon:'📑',label:'История продаж'},
            {id:'products',icon:'💎',label:'Каталог / Остатки'}],
  CLIENT: [{id:'catalog',icon:'💎',label:'Каталог'},
            {id:'my_purchases',icon:'🛍️',label:'Мои покупки'},
            {id:'reviews',icon:'⭐',label:'Отзывы'}],
};
function buildNav(){
  const items=PAGES[ROLE]||[];
  let html='';
  items.forEach(it=>{
    if(it.sec){html+=`<div class="nav-section">${it.sec}</div>`;return;}
    html+=`<a class="nav-item" data-page="${it.id}" onclick="navigate('${it.id}')" href="#">
      <span class="nav-icon">${it.icon}</span><span>${it.label}</span></a>`;
  });
  document.getElementById('nav').innerHTML=html;
}
function navigate(page){
  document.querySelectorAll('.nav-item').forEach(el=>el.classList.toggle('active',el.dataset.page===page));
  const titles={dashboard:'Дашборд',sales:'Продажи',clients:'Клиенты',products:'Товары / Остатки',
    stock:'Остатки',orders:'Заказы поставщикам',suppliers:'Поставщики',stores:'Магазины',
    reviews:'Отзывы',reports:'Отчёты',sale_new:'Оформить продажу',catalog:'Каталог',my_purchases:'Мои покупки'};
  document.getElementById('topbar-title').textContent=titles[page]||page;
  const fn={dashboard:pgDashboard,sales:pgSales,clients:pgClients,products:pgProducts,
    stock:pgStock,orders:pgOrders,suppliers:pgSuppliers,stores:pgStores,
    reviews:pgReviews,reports:pgReports,sale_new:pgSaleNew,catalog:pgCatalog,
    my_purchases:pgMyPurchases}[page];
  if(fn)fn();else setPage('<div class="empty-state"><div class="esi">🔧</div><p>Страница в разработке</p></div>');
}
function toggleSidebar(){document.getElementById('sidebar').classList.toggle('collapsed');}

// ═══════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════
async function pgDashboard(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    if(ROLE==='CASHIER'){
      // Кассир: последние продажи своего магазина
      const storeId=MY_STORE?MY_STORE.id:'';
      const sales=await get('/sales',{store_id:storeId});
      setPage(`
      <div id="page-alert"></div>
      <div class="stats-grid">
        <div class="stat-card"><div class="stat-value">${fmt(sales.length)}</div><div class="stat-label">Продаж в магазине</div><div class="stat-icon">🛒</div></div>
        <div class="stat-card"><div class="stat-value">${fmtMoney(sales.reduce((s,x)=>s+(x.total||0),0))}</div><div class="stat-label">Общая выручка</div><div class="stat-icon">💰</div></div>
        <div class="stat-card"><div class="stat-value">${MY_STORE?MY_STORE.address.split(',')[1]||MY_STORE.address:'—'}</div><div class="stat-label">Мой магазин</div><div class="stat-icon">🏪</div></div>
      </div>
      <div class="card"><div class="card-title">🛒 Последние продажи</div>
        <div class="tbl-wrap"><table>
          <thead><tr><th>Дата</th><th>Клиент</th><th>Товары</th><th>Сумма</th><th>Оплата</th></tr></thead>
          <tbody>${sales.slice(0,10).map(s=>`<tr>
            <td>${fmtDate(s.date)}</td><td>${esc(s.client||'—')}</td>
            <td><small>${esc(s.store)}</small></td>
            <td><b>${fmtMoney(s.total)}</b></td><td>${esc(s.payment)}</td></tr>`).join('')}
          </tbody></table></div></div>`);
      return;
    }
    if(ROLE==='MANAGER'){
      const storeId=MY_STORE?MY_STORE.id:'';
      const [sales,stock,orders]=await Promise.all([
        get('/sales',{store_id:storeId}),
        storeId?get('/stores/'+storeId+'/stock',{threshold:'3'}):[],
        get('/orders',{store_id:storeId})]);
      const activeOrders=orders.filter(o=>['ожидается','В пути','В обработке'].includes(o.status)).length;
      const lowStock=stock.filter(s=>s.qty<=2).length;
      setPage(`
      <div id="page-alert"></div>
      <div style="font-family:'Cormorant Garamond',serif;font-size:20px;margin-bottom:16px;color:var(--ash)">
        Магазин: <b style="color:var(--ink)">${esc(MY_STORE?MY_STORE.address:'—')}</b>
      </div>
      <div class="stats-grid">
        <div class="stat-card"><div class="stat-value">${fmt(sales.length)}</div><div class="stat-label">Продаж</div><div class="stat-icon">🛒</div></div>
        <div class="stat-card"><div class="stat-value">${fmtMoney(sales.reduce((s,x)=>s+(x.total||0),0))}</div><div class="stat-label">Выручка</div><div class="stat-icon">💰</div></div>
        <div class="stat-card"><div class="stat-value">${fmt(activeOrders)}</div><div class="stat-label">Активных заказов</div><div class="stat-icon">📋</div></div>
        <div class="stat-card" style="${lowStock>0?'border-left-color:var(--danger)':''}">
          <div class="stat-value" style="${lowStock>0?'color:var(--danger)':''}">${fmt(lowStock)}</div>
          <div class="stat-label">Критический остаток</div><div class="stat-icon">⚠️</div></div>
      </div>
      <div class="card"><div class="card-title">🛒 Последние продажи магазина</div>
        <div class="tbl-wrap"><table>
          <thead><tr><th>Дата</th><th>Клиент</th><th>Сумма</th><th>Оплата</th><th>Кассир</th></tr></thead>
          <tbody>${sales.slice(0,8).map(s=>`<tr>
            <td>${fmtDate(s.date)}</td><td>${esc(s.client||'—')}</td>
            <td><b>${fmtMoney(s.total)}</b></td><td>${esc(s.payment)}</td>
            <td><small>${esc(s.cashier)}</small></td></tr>`).join('')}
          </tbody></table></div></div>
      ${lowStock>0?`<div class="card" style="border-left:3px solid var(--danger)">
        <div class="card-title" style="color:var(--danger)">⚠️ Критические остатки</div>
        <div class="items-list">${stock.filter(s=>s.qty<=2).map(s=>`
          <div class="item-row"><span>${esc(s.name)}</span>
          <b style="color:var(--danger)">${s.qty} шт</b></div>`).join('')}
        </div></div>`:''}
      `);
      return;
    }
    // ADMIN dashboard
    const [sales,products,stores,orders]=await Promise.all([
      get('/sales'),get('/products'),get('/stores'),get('/orders')]);
    const totalRev=sales.reduce((s,x)=>s+(x.total||0),0);
    const activeOrders=orders.filter(o=>['ожидается','В пути','В обработке'].includes(o.status)).length;
    setPage(`
    <div id="page-alert"></div>
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-value">${fmt(sales.length)}</div><div class="stat-label">Всего продаж</div><div class="stat-icon">🛒</div></div>
      <div class="stat-card"><div class="stat-value">${fmtMoney(totalRev)}</div><div class="stat-label">Общая выручка</div><div class="stat-icon">💰</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(products.length)}</div><div class="stat-label">Товаров</div><div class="stat-icon">💎</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(stores.length)}</div><div class="stat-label">Магазинов</div><div class="stat-icon">🏪</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(activeOrders)}</div><div class="stat-label">Активных заказов</div><div class="stat-icon">📋</div></div>
    </div>
    <div class="card"><div class="card-title">💡 Последние продажи</div>
      <div class="tbl-wrap"><table>
        <thead><tr><th>Дата</th><th>Клиент</th><th>Магазин</th><th>Сумма</th><th>Оплата</th></tr></thead>
        <tbody>${sales.slice(0,8).map(s=>`<tr>
          <td>${fmtDate(s.date)}</td><td>${esc(s.client)}</td>
          <td><span class="tag">${esc(s.store.split(',').slice(-1)[0]||s.store)}</span></td>
          <td><b>${fmtMoney(s.total)}</b></td><td>${esc(s.payment)}</td></tr>`).join('')}
        </tbody></table></div></div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// ═══════════════════════════════════════════════════════════════
// SALES
// ═══════════════════════════════════════════════════════════════
let salesData=[],salesPage=1;
async function pgSales(fromVal='',toVal='',storeIdParam=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    // Кассир и менеджер видят только свой магазин
    const fixedStore=(ROLE==='CASHIER'||ROLE==='MANAGER')&&MY_STORE?MY_STORE.id:storeIdParam;
    const [data,stores]=await Promise.all([
      get('/sales',{from:fromVal,to:toVal,store_id:fixedStore}),
      ROLE==='ADMIN'?get('/stores'):Promise.resolve([])]);
    salesData=data;salesPage=1;
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${s.id==storeIdParam?'selected':''}>${esc(s.address)}</option>`).join('');
    const canAdd=ROLE==='ADMIN'||ROLE==='CASHIER';
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="padding:14px 20px;margin-bottom:0">
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="f-from" value="${fromVal}"></div>
        <div class="filter-group"><label>По</label><input type="date" id="f-to" value="${toVal}"></div>
        ${ROLE==='ADMIN'?`<div class="filter-group"><label>Магазин</label>
          <select id="f-store"><option value="">Все магазины</option>${storeOpts}</select></div>`:''}
        <button class="btn btn-primary btn-sm" onclick="pgSales(
          document.getElementById('f-from').value,
          document.getElementById('f-to').value,
          ${ROLE==='ADMIN'?'document.getElementById(\'f-store\').value':'\'\''})">Применить</button>
        ${canAdd?'<button class="btn btn-outline btn-sm" onclick="modalNewSale()">+ Новая продажа</button>':''}
      </div>
    </div>
    <div class="card"><div id="sales-table"></div></div>`);
    renderSalesTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderSalesTable(){
  const {items,total,page}=paginate(salesData,salesPage,PAGE_SIZE);
  document.getElementById('sales-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Дата</th><th>Клиент</th><th>Телефон</th><th>Магазин</th><th>Кассир</th><th>Сумма</th><th>Оплата</th><th></th></tr></thead>
      <tbody>${items.map(s=>`<tr>
        <td>${s.id}</td><td>${fmtDate(s.date)}</td>
        <td>${esc(s.client||'—')}</td>
        <td><small>${esc(s.client_phone||'')}</small></td>
        <td><small>${esc(s.store)}</small></td>
        <td><small>${esc(s.cashier)}</small></td>
        <td><b>${fmtMoney(s.total)}</b></td>
        <td>${esc(s.payment)}</td>
        <td><button class="btn btn-ghost btn-xs" onclick="viewSale(${s.id})">Детали</button></td>
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setSalesPage')}`;
}
function setSalesPage(p){salesPage=p;renderSalesTable();}
async function viewSale(id){
  try{
    const s=await get('/sales/'+id);
    openModal('Продажа #'+id,`
      <div class="form-row" style="margin-bottom:12px">
        <div><label>Клиент</label><p>${esc(s.client)}</p></div>
        <div><label>Дата</label><p>${fmtDate(s.date)}</p></div>
        <div><label>Магазин</label><p>${esc(s.store)}</p></div>
        <div><label>Кассир</label><p>${esc(s.cashier)}</p></div>
        <div><label>Оплата</label><p>${esc(s.payment)}</p></div>
        <div><label>Итого</label><p><b>${fmtMoney(s.total)}</b></p></div>
      </div>
      <hr class="separator">
      <div class="card-title" style="font-size:15px">Позиции</div>
      <div class="items-list">${(s.items||[]).map(i=>`
        <div class="item-row"><span>${esc(i.name)}</span>
        <span>${i.qty} шт × ${fmtMoney(i.price)}</span></div>`).join('')}
      </div>`,'<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// NEW SALE — Кассир выбирает клиента по телефону, магазин авто
// ═══════════════════════════════════════════════════════════════
let saleCartItems=[];
let foundClient=null;
async function pgSaleNew(){
  try{
    const storeId=MY_STORE?MY_STORE.id:'';
    const products=await get('/products',{store_id:storeId});
    saleCartItems=[];foundClient=null;
    const prodOpts=products.map(p=>`<option value="${p.article}" data-price="${p.price}" data-name="${esc(p.name)}" data-stock="${p.stock_quantity||0}">${esc(p.name)} [арт.${p.article}] — ${fmtMoney(p.price)} (ост:${p.stock_quantity||0})</option>`).join('');
    setPage(`
    <div id="page-alert"></div>
    <div style="display:grid;grid-template-columns:1fr 380px;gap:16px;align-items:start">
      <div>
        <div class="card">
          <div class="card-title">👤 Клиент — поиск по телефону</div>
          <div style="display:flex;gap:8px;align-items:flex-end">
            <div class="form-group" style="flex:1;margin:0"><label>Номер телефона</label>
              <input id="sn-phone" type="text" placeholder="+7 (XXX) XXX-XX-XX"></div>
            <button class="btn btn-outline btn-sm" onclick="searchClientByPhone()">Найти</button>
          </div>
          <div id="sn-client-info" style="margin-top:10px"></div>
        </div>
        <div class="card">
          <div class="card-title">💎 Добавить товар (поиск по артикулу / названию)</div>
          <div class="form-row">
            <div class="form-group"><label>Товар</label>
              <select id="sn-product"><option value="">— Выберите —</option>${prodOpts}</select></div>
            <div class="form-group"><label>Кол-во</label>
              <input type="number" id="sn-qty" value="1" min="1" style="width:80px"></div>
          </div>
          <button class="btn btn-outline btn-sm" onclick="saleAddItem()">+ В корзину</button>
        </div>
        <div class="card">
          <div class="card-title">🛒 Корзина</div>
          <div id="sn-cart"><div class="empty-state" style="padding:16px"><div class="esi">🛒</div><p>Пусто</p></div></div>
        </div>
      </div>
      <div class="card" style="position:sticky;top:0">
        <div class="card-title">💳 Оплата</div>
        <div style="font-size:13px;color:var(--ash);margin-bottom:6px">Магазин:</div>
        <div style="font-size:13px;font-weight:500;margin-bottom:14px">${esc(MY_STORE?MY_STORE.address:'—')}</div>
        <div class="form-group"><label>Способ оплаты</label>
          <select id="sn-payment"><option>Карта</option><option>Наличные</option></select></div>
        <hr class="separator">
        <div style="font-size:12px;color:var(--ash);margin-bottom:4px">Итого:</div>
        <div id="sn-total" style="font-family:'Cormorant Garamond',serif;font-size:32px;color:var(--gold);margin-bottom:16px">0 ₽</div>
        <button class="btn btn-primary" style="width:100%;justify-content:center;padding:12px" onclick="submitSale()">Оформить продажу</button>
      </div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
async function searchClientByPhone(){
  const phone=document.getElementById('sn-phone').value.trim();
  if(!phone)return;
  const el=document.getElementById('sn-client-info');
  try{
    const clients=await get('/clients',{search:phone});
    if(!clients.length){
      el.innerHTML=`<div class="alert alert-err">Клиент с телефоном "${esc(phone)}" не найден. <a href="#" onclick="showRegForm()" style="color:var(--gold)">Зарегистрировать?</a></div>`;
      foundClient=null;return;}
    foundClient=clients[0];
    el.innerHTML=`<div class="alert alert-ok" style="display:flex;justify-content:space-between;align-items:center">
      <span>✓ <b>${esc(foundClient.fio||'Клиент')}</b> — ${esc(foundClient.phone)}</span>
      <span style="font-size:11px;color:var(--success)">ID: ${foundClient.id}</span></div>`;
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}
function saleAddItem(){
  const sel=document.getElementById('sn-product');
  const opt=sel.options[sel.selectedIndex];
  if(!opt||!opt.value)return;
  const qty=parseInt(document.getElementById('sn-qty').value)||1;
  const art=parseInt(opt.value);
  const price=parseInt(opt.dataset.price);
  const name=opt.dataset.name;
  const stock=parseInt(opt.dataset.stock||0);
  const existing=saleCartItems.find(i=>i.article===art);
  const newQty=(existing?existing.qty:0)+qty;
  if(newQty>stock){showAlert(`Недостаточно товара: доступно ${stock} шт`,'err','page-alert');return;}
  if(existing)existing.qty+=qty;
  else saleCartItems.push({article:art,name,price,qty,stock});
  renderSaleCart();
}
function saleRemoveItem(idx){saleCartItems.splice(idx,1);renderSaleCart();}
function renderSaleCart(){
  const cart=document.getElementById('sn-cart');
  if(!saleCartItems.length){
    cart.innerHTML='<div class="empty-state" style="padding:16px"><div class="esi">🛒</div><p>Пусто</p></div>';
    document.getElementById('sn-total').textContent='0 ₽';return;}
  const total=saleCartItems.reduce((s,i)=>s+i.price*i.qty,0);
  cart.innerHTML=`<div class="items-list">${saleCartItems.map((i,idx)=>`
    <div class="item-row">
      <div><div>${esc(i.name)}</div><small style="color:var(--smoke)">${i.qty} × ${fmtMoney(i.price)}</small></div>
      <div style="display:flex;align-items:center;gap:8px">
        <b>${fmtMoney(i.price*i.qty)}</b>
        <span class="item-row-del" onclick="saleRemoveItem(${idx})">✕</span>
      </div></div>`).join('')}</div>`;
  document.getElementById('sn-total').textContent=fmtMoney(total);
}
async function submitSale(){
  if(!foundClient)return showAlert('Найдите клиента по телефону','err','page-alert');
  if(!saleCartItems.length)return showAlert('Добавьте товары','err','page-alert');
  if(!MY_STORE)return showAlert('Магазин не определён','err','page-alert');
  const payment=document.getElementById('sn-payment').value;
  try{
    await post('/sales',{client_id:foundClient.id,cashier_snils:REF.trim(),
      store_id:MY_STORE.id,payment_method:payment,
      items:saleCartItems.map(i=>({article:i.article,price:i.price,qty:i.qty}))});
    showAlert('Продажа успешно оформлена!','ok','page-alert');
    saleCartItems=[];foundClient=null;
    document.getElementById('sn-client-info').innerHTML='';
    renderSaleCart();
    document.getElementById('sn-phone').value='';
  }catch(e){showAlert(e.message,'err','page-alert');}
}

// Модальная продажа для Admin
async function modalNewSale(){
  try{
    const [products,clients,stores]=await Promise.all([get('/products'),get('/clients'),get('/stores')]);
    const prodOpts=products.map(p=>`<option value="${p.article}" data-price="${p.price}" data-name="${esc(p.name)}">${esc(p.name)} — ${fmtMoney(p.price)}</option>`).join('');
    const clientOpts=clients.map(c=>`<option value="${c.id}">${esc(c.fio||c.phone)}</option>`).join('');
    saleCartItems=[];
    openModal('Новая продажа',`
      <div class="form-row">
        <div class="form-group"><label>Клиент</label>
          <select id="mn-client"><option value="">— Выберите —</option>${clientOpts}</select></div>
        <div class="form-group"><label>Магазин</label>
          <select id="mn-store">${stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('')}</select></div>
      </div>
      <div class="form-row">
        <div class="form-group"><label>СНИЛС кассира</label><input id="mn-cashier" value="11111111111111"></div>
        <div class="form-group"><label>Оплата</label>
          <select id="mn-payment"><option>Карта</option><option>Наличные</option></select></div>
      </div>
      <div class="form-row">
        <div class="form-group"><label>Товар</label>
          <select id="mn-product"><option value="">— Выберите —</option>${prodOpts}</select></div>
        <div class="form-group"><label>Кол-во</label><input type="number" id="mn-qty" value="1" min="1" style="width:80px"></div>
      </div>
      <button class="btn btn-outline btn-sm" onclick="mnAddItem()">+ Добавить</button>
      <div id="mn-cart" style="margin-top:10px"></div>
      <div id="mn-total" style="font-weight:600;margin-top:6px"></div>`,
      `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
       <button class="btn btn-primary" onclick="mnSubmit()">Оформить</button>`);
    renderMnCart();
  }catch(e){alert(e.message);}
}
function mnAddItem(){
  const sel=document.getElementById('mn-product');const opt=sel.options[sel.selectedIndex];
  if(!opt||!opt.value)return;
  const qty=parseInt(document.getElementById('mn-qty').value)||1;
  const art=parseInt(opt.value),price=parseInt(opt.dataset.price),name=opt.dataset.name;
  const ex=saleCartItems.find(i=>i.article===art);
  if(ex)ex.qty+=qty;else saleCartItems.push({article:art,name,price,qty});
  renderMnCart();
}
function mnRemoveItem(idx){saleCartItems.splice(idx,1);renderMnCart();}
function renderMnCart(){
  const el=document.getElementById('mn-cart');if(!el)return;
  el.innerHTML=`<div class="items-list">${saleCartItems.map((i,idx)=>`
    <div class="item-row"><span>${esc(i.name)} × ${i.qty}</span>
    <span>${fmtMoney(i.price*i.qty)}<span class="item-row-del" onclick="mnRemoveItem(${idx})">✕</span></span></div>`).join('')}</div>`;
  const tot=document.getElementById('mn-total');
  if(tot)tot.textContent='Итого: '+fmtMoney(saleCartItems.reduce((s,i)=>s+i.price*i.qty,0));
}
async function mnSubmit(){
  const clientId=parseInt(document.getElementById('mn-client').value);
  const storeId=parseInt(document.getElementById('mn-store').value);
  const cashierSnils=document.getElementById('mn-cashier').value.trim();
  const payment=document.getElementById('mn-payment').value;
  if(!clientId||!cashierSnils||!saleCartItems.length)return alert('Заполните все поля и добавьте товары');
  try{
    await post('/sales',{client_id:clientId,cashier_snils:cashierSnils,store_id:storeId,
      payment_method:payment,items:saleCartItems.map(i=>({article:i.article,price:i.price,qty:i.qty}))});
    closeModal();pgSales();
  }catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// CLIENTS
// ═══════════════════════════════════════════════════════════════
let clientsData=[],clientsPage=1;
async function pgClients(srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    clientsData=await get('/clients',{search:srch});clientsPage=1;
    // Для менеджера — только клиенты его магазина
    if(ROLE==='MANAGER'&&MY_STORE){
      clientsData=await get('/clients',{search:srch,store_id:MY_STORE.id}).catch(()=>clientsData);
    }
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="padding:14px 20px;margin-bottom:0">
      <div class="filters">
        <div class="filter-group"><label>Поиск</label>
          <input id="cl-srch" type="text" placeholder="ФИО или телефон" value="${esc(srch)}"></div>
        <button class="btn btn-primary btn-sm" onclick="pgClients(document.getElementById('cl-srch').value)">Найти</button>
      </div>
    </div>
    <div class="card"><div id="clients-table"></div></div>`);
    renderClientsTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderClientsTable(){
  const {items,total,page}=paginate(clientsData,clientsPage,PAGE_SIZE);
  document.getElementById('clients-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>ФИО</th><th>Телефон</th><th>Email</th><th></th></tr></thead>
      <tbody>${items.map(c=>`<tr>
        <td>${esc(c.fio||'—')}</td><td>${esc(c.phone)}</td><td>${esc(c.email||'—')}</td>
        <td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick="viewClient(${c.id})">Профиль</button>
          <button class="btn btn-outline btn-xs" onclick="editClient(${c.id},'${esc(c.fio)}','${esc(c.phone)}','${esc(c.email)}')">✏</button>
        </td></tr>`).join('')}
      </tbody></table></div>
    ${paginationHtml(page,total,'setClientsPage')}`;
}
function setClientsPage(p){clientsPage=p;renderClientsTable();}
async function viewClient(id){
  try{
    const [c,sales]=await Promise.all([get('/clients/'+id),get('/clients/'+id+'/sales')]);
    openModal('Профиль клиента',`
      <div class="stats-grid" style="grid-template-columns:1fr 1fr 1fr;margin-bottom:14px">
        <div class="stat-card"><div class="stat-value">${fmt(c.purchase_count)}</div><div class="stat-label">Покупок</div></div>
        <div class="stat-card"><div class="stat-value">${fmtMoney(c.total_spent)}</div><div class="stat-label">Сумма</div></div>
        <div class="stat-card"><div class="stat-value">${c.purchase_count?fmtMoney(c.total_spent/c.purchase_count):'—'}</div><div class="stat-label">Средний чек</div></div>
      </div>
      <div class="form-row">
        <div><label>ФИО</label><p>${esc(c.fio||'—')}</p></div>
        <div><label>Телефон</label><p>${esc(c.phone)}</p></div>
        <div><label>Email</label><p>${esc(c.email||'—')}</p></div>
      </div>
      <hr class="separator">
      <div class="card-title" style="font-size:15px">Последние покупки</div>
      <div class="items-list">${sales.slice(0,5).map(s=>`
        <div class="item-row"><span>${fmtDate(s.date)} — ${esc(s.store)}</span><b>${fmtMoney(s.total)}</b></div>`).join('')
        ||'<p style="color:var(--smoke)">Нет покупок</p>'}
      </div>`,'<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}
async function editClient(id,fio,phone,email){
  openModal('Редактировать клиента',`
    <div class="form-group"><label>ФИО</label><input id="ec-fio" value="${esc(fio)}"></div>
    <div class="form-group"><label>Телефон</label><input id="ec-phone" value="${esc(phone)}"></div>
    <div class="form-group"><label>Email</label><input id="ec-email" value="${esc(email)}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveClient(${id})">Сохранить</button>`);
}
async function saveClient(id){
  try{
    await put('/clients/'+id,{fio:document.getElementById('ec-fio').value,
      phone:document.getElementById('ec-phone').value,email:document.getElementById('ec-email').value});
    closeModal();pgClients();
  }catch(e){alert(e.message);}
}
JS_EOF
ok "app.js part 1 (auth, dashboard, sales, cashier)"


cat >> "$PROJ/frontend/js/app.js" << 'JS2_EOF'

// ═══════════════════════════════════════════════════════════════
// PRODUCTS — только менеджер и админ могут добавлять
// Для кассира — каталог совмещён с остатками его магазина
// ═══════════════════════════════════════════════════════════════
let productsData=[],productsPage=1;
async function pgProducts(cat='',srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const storeId=(ROLE==='CASHIER'&&MY_STORE)?MY_STORE.id:'';
    productsData=await get('/products',{category:cat,search:srch,store_id:storeId});
    productsPage=1;
    const cats=[...new Set(productsData.map(p=>p.category))].sort();
    const canEdit=ROLE==='ADMIN'||ROLE==='MANAGER';
    const isCashier=ROLE==='CASHIER';
    setPage(`
    <div id="page-alert"></div>
    ${isCashier?`<div style="font-size:12px;color:var(--smoke);margin-bottom:10px">
      Магазин: <b>${esc(MY_STORE?MY_STORE.address:'—')}</b> — показаны остатки вашего магазина</div>`:''}
    <div class="card" style="padding:14px 20px;margin-bottom:0">
      <div class="filters">
        <div class="filter-group"><label>Категория</label>
          <select id="p-cat">
            <option value="">Все категории</option>
            ${cats.map(c=>`<option ${c===cat?'selected':''}>${esc(c)}</option>`).join('')}
          </select></div>
        <div class="filter-group"><label>Поиск ${isCashier?'(название / арт.)':''}</label>
          <input id="p-srch" type="text" placeholder="${isCashier?'Артикул или название':'Название'}" value="${esc(srch)}"></div>
        <button class="btn btn-primary btn-sm" onclick="pgProducts(document.getElementById('p-cat').value,document.getElementById('p-srch').value)">Найти</button>
        ${canEdit?'<button class="btn btn-outline btn-sm" onclick="editProduct(null)">+ Добавить товар</button>':''}
      </div>
    </div>
    <div class="card"><div id="products-table"></div></div>`);
    renderProductsTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderProductsTable(){
  const {items,total,page}=paginate(productsData,productsPage,PAGE_SIZE);
  const canEdit=ROLE==='ADMIN'||ROLE==='MANAGER';
  const showStock=ROLE==='CASHIER'||(productsData[0]&&productsData[0].stock_quantity!==undefined);
  document.getElementById('products-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th>
        ${showStock?'<th>Остаток</th>':''}
        ${canEdit?'<th></th>':''}</tr></thead>
      <tbody>${items.map(p=>{
        const lvl=p.stock_quantity<=0?'danger':p.stock_quantity<=2?'warning':'success';
        return`<tr>
          <td><code>${p.article}</code></td>
          <td><a href="#" onclick="viewProductDetail(${p.article})" style="color:var(--gold)">${esc(p.name)}</a></td>
          <td><span class="badge badge-gold">${esc(p.category)}</span></td>
          <td><b>${fmtMoney(p.price)}</b></td>
          ${showStock?`<td><span class="badge badge-${lvl}">${p.stock_quantity} шт</span></td>`:''}
          ${canEdit?`<td class="td-actions">
            <button class="btn btn-ghost btn-xs" onclick="editProduct(${p.article},'${esc(p.name)}','${esc(p.category)}',${p.price})">✏</button>
            ${ROLE==='ADMIN'?`<button class="btn btn-danger btn-xs" onclick="deleteProduct(${p.article})">🗑</button>`:''}
          </td>`:''}
        </tr>`;}).join('')}
      </tbody></table></div>
    ${paginationHtml(page,total,'setProductsPage')}`;
}
function setProductsPage(p){productsPage=p;renderProductsTable();}

async function viewProductDetail(article){
  try{
    const [p,stocks]=await Promise.all([
      get('/products/'+article),
      get('/products/'+article+'/stock-all')]);
    const catIcon={'Кольца':'💍','Серьги':'💎','Браслеты':'✨','Подвески':'🔮','Цепочки':'⛓️','Часы':'⌚','Броши':'🌸'}[p.category]||'💎';
    const sizes={
      'Кольца':['15','15.5','16','16.5','17','17.5','18','18.5','19','19.5','20','21','22'],
      'Браслеты':['16 см','17 см','18 см','19 см','20 см','21 см'],
      'Цепочки':['40 см','45 см','50 см','55 см','60 см'],
    };
    const sizeOpts=sizes[p.category];
    openModal(p.name,`
      <div style="text-align:center;font-size:56px;margin-bottom:12px">${catIcon}</div>
      <div style="text-align:center;margin-bottom:6px"><span class="badge badge-gold">${esc(p.category)}</span></div>
      <div style="text-align:center;font-family:'Cormorant Garamond',serif;font-size:30px;color:var(--gold);margin:10px 0">${fmtMoney(p.price)}</div>
      <div style="text-align:center;font-size:12px;color:var(--smoke);margin-bottom:16px">Артикул: ${p.article}</div>
      ${sizeOpts?`<div class="form-group"><label>Выбрать размер</label>
        <select style="max-width:200px;margin:0 auto;display:block">
          <option value="">— Размер —</option>
          ${sizeOpts.map(s=>`<option>${s}</option>`).join('')}
        </select></div><hr class="separator">`:''}
      <div class="card-title" style="font-size:15px;margin-bottom:10px">📦 Наличие в магазинах сети</div>
      <div class="items-list">
        ${stocks.length?stocks.map(s=>{
          const lvl=s.qty<=0?'danger':s.qty<=2?'warning':'success';
          const lbl=s.qty<=0?'Нет в наличии':s.qty<=2?'Мало':'В наличии';
          return`<div class="item-row">
            <div><div style="font-size:13px">${esc(s.address)}</div></div>
            <span class="badge badge-${lvl}">${lbl}: ${s.qty} шт</span>
          </div>`;}).join('')
        :'<p style="color:var(--smoke);font-size:13px">Нет данных об остатках</p>'}
      </div>
      <div style="margin-top:14px;padding:10px;background:var(--cream);border-radius:var(--radius);font-size:12px;color:var(--ash)">
        ℹ️ Онлайн-заказ недоступен. Приобрести товар можно в любом магазине сети.
      </div>`,
      `<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>`);
  }catch(e){alert(e.message);}
}

function editProduct(art,name='',cat='',price=0){
  // Артикул не вводится — определяется автоматически
  openModal(art?'Редактировать товар':'Новый товар',`
    <div class="form-group"><label>Название</label><input id="ep-name" value="${esc(name)}" placeholder="Кольцо «Романтика»"></div>
    <div class="form-group"><label>Категория</label>
      <select id="ep-cat">
        ${['Кольца','Серьги','Браслеты','Подвески','Цепочки','Часы','Броши'].map(c=>`<option ${c===cat?'selected':''}>${c}</option>`).join('')}
      </select></div>
    <div class="form-group"><label>Цена (руб.)</label><input id="ep-price" type="number" value="${price}" min="1"></div>
    ${art?'':`<div style="font-size:12px;color:var(--smoke);margin-top:-8px">
      Артикул будет присвоен автоматически.</div>`}`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveProduct(${art||0})">Сохранить</button>`);
}
async function saveProduct(art){
  const name=document.getElementById('ep-name').value.trim();
  const cat=document.getElementById('ep-cat').value;
  const price=parseInt(document.getElementById('ep-price').value);
  if(!name||price<=0)return alert('Заполните все поля');
  try{
    if(art) await put('/products/'+art,{name,category:cat,price});
    else    await post('/products',{name,category:cat,price});
    closeModal();pgProducts();
  }catch(e){alert(e.message);}
}
async function deleteProduct(art){
  if(!confirm('Удалить товар?'))return;
  try{await del('/products/'+art);pgProducts();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// STOCK — менеджер видит только свой магазин
// ═══════════════════════════════════════════════════════════════
async function pgStock(storeIdOverride='',thresh=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const stores=ROLE==='ADMIN'?await get('/stores'):[];
    // Менеджер и кассир — только свой
    const fixedId=(ROLE==='MANAGER'||ROLE==='CASHIER')&&MY_STORE?MY_STORE.id:null;
    let storeId=fixedId||storeIdOverride;
    if(!storeId&&stores.length) storeId=stores[0].id;
    const stock=storeId?await get('/stores/'+storeId+'/stock',{threshold:thresh}):[];
    const storeOpts=ROLE==='ADMIN'?stores.map(s=>`<option value="${s.id}" ${s.id==storeId?'selected':''}>${esc(s.address)}</option>`).join(''):'';
    setPage(`
    <div id="page-alert"></div>
    ${fixedId?`<div style="font-size:13px;font-weight:500;margin-bottom:12px">📦 Магазин: ${esc(MY_STORE.address)}</div>`:''}
    <div class="card" style="padding:14px 20px;margin-bottom:0">
      <div class="filters">
        ${ROLE==='ADMIN'?`<div class="filter-group"><label>Магазин</label>
          <select id="st-store">${storeOpts}</select></div>`:''}
        <div class="filter-group"><label>Порог ≤</label>
          <input type="number" id="st-thresh" value="${esc(thresh)}" placeholder="Все" style="width:90px"></div>
        <button class="btn btn-primary btn-sm" onclick="pgStock(${ROLE==='ADMIN'?'document.getElementById(\'st-store\').value':'\'\''}, document.getElementById('st-thresh').value)">Применить</button>
      </div>
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th><th>Остаток</th><th>Статус</th><th></th></tr></thead>
        <tbody>${stock.map(s=>{
          const lvl=s.qty<=0?'danger':s.qty<=2?'warning':'success';
          const lbl=s.qty<=0?'Нет в наличии':s.qty<=2?'Критический':s.qty<=5?'Мало':'В наличии';
          return`<tr>
            <td><code>${s.article}</code></td>
            <td><a href="#" onclick="viewProductDetail(${s.article})" style="color:var(--gold)">${esc(s.name)}</a></td>
            <td><span class="badge badge-gold">${esc(s.category)}</span></td>
            <td>${fmtMoney(s.price)}</td>
            <td><b style="color:var(--${lvl==='danger'?'danger':lvl==='warning'?'warning':'success'})">${s.qty}</b></td>
            <td><span class="badge badge-${lvl}">${lbl}</span></td>
            <td><button class="btn btn-ghost btn-xs" onclick="editStockQty(${s.stock_id},${storeId},${s.qty})">✏</button></td>
          </tr>`;}).join('')||`<tr><td colspan="7"><div class="empty-state" style="padding:20px">
            <div class="esi">📦</div><p>Нет данных</p></div></td></tr>`}
        </tbody></table></div>
      ${stock.length?`<hr class="separator">
      <div class="card-title" style="font-size:15px">📊 Визуализация</div>
      <div class="chart-bar-wrap">${stock.slice(0,10).map(s=>{
        const maxQ=Math.max(...stock.map(x=>x.qty),1);
        const pct=Math.round((s.qty/maxQ)*100);
        const clr=s.qty<=0?'var(--danger)':s.qty<=2?'var(--warning)':'';
        return`<div class="chart-bar-row">
          <div class="chart-bar-label">${esc(s.name.substring(0,18))}</div>
          <div class="chart-bar-track"><div class="chart-bar-fill" style="width:${pct}%;${clr?'background:'+clr:''}">${s.qty}</div></div>
          <div class="chart-bar-val">${s.qty} шт</div></div>`;}).join('')}
      </div>`:''}`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function editStockQty(stockId,storeId,cur){
  openModal('Изменить количество',`
    <div class="form-group"><label>Текущее: ${cur} шт</label>
      <input id="sq-qty" type="number" value="${cur}" min="0"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveStockQty(${stockId},${storeId})">Сохранить</button>`);
}
async function saveStockQty(stockId,storeId){
  try{
    await put('/stock/'+stockId,{qty:parseInt(document.getElementById('sq-qty').value),store_id:storeId});
    closeModal();pgStock(storeId);
  }catch(e){alert(e.message);}
}
JS2_EOF
ok "app.js part 2 (products, stock)"


cat >> "$PROJ/frontend/js/app.js" << 'JS3_EOF'

// ═══════════════════════════════════════════════════════════════
// ORDERS — менеджер видит только свой магазин, без выбора
// ═══════════════════════════════════════════════════════════════
let ordersData=[],ordersPage=1;
async function pgOrders(statusF='',suppF='',storeF=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const fixedStore=(ROLE==='MANAGER')&&MY_STORE?MY_STORE.id:storeF;
    const [data,suppliers,stores]=await Promise.all([
      get('/orders',{status:statusF,supplier_id:suppF,store_id:fixedStore}),
      get('/suppliers'),
      ROLE==='ADMIN'?get('/stores'):Promise.resolve([])]);
    ordersData=data;ordersPage=1;
    const suppOpts=suppliers.map(s=>`<option value="${s.id}" ${s.id==suppF?'selected':''}>${esc(s.name)}</option>`).join('');
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${s.id==storeF?'selected':''}>${esc(s.address)}</option>`).join('');
    const statuses=['','В обработке','В пути','Доставлен','ожидается','Отменен'];
    const canCreate=ROLE==='ADMIN'||ROLE==='MANAGER';
    setPage(`
    <div id="page-alert"></div>
    ${ROLE==='MANAGER'?`<div style="font-size:13px;font-weight:500;margin-bottom:12px">📋 Магазин: ${esc(MY_STORE?MY_STORE.address:'—')}</div>`:''}
    <div class="card" style="padding:14px 20px;margin-bottom:0">
      <div class="filters">
        <div class="filter-group"><label>Статус</label>
          <select id="or-status">${statuses.map(s=>`<option ${s===statusF?'selected':''}>${s||'Все статусы'}</option>`).join('')}</select></div>
        <div class="filter-group"><label>Поставщик</label>
          <select id="or-supp"><option value="">Все поставщики</option>${suppOpts}</select></div>
        ${ROLE==='ADMIN'?`<div class="filter-group"><label>Магазин</label>
          <select id="or-store"><option value="">Все магазины</option>${storeOpts}</select></div>`:''}
        <button class="btn btn-primary btn-sm" onclick="pgOrders(
          document.getElementById('or-status').value,
          document.getElementById('or-supp').value,
          ${ROLE==='ADMIN'?'document.getElementById(\'or-store\').value':'\'\''})">Применить</button>
        ${canCreate?'<button class="btn btn-outline btn-sm" onclick="modalNewOrder()">+ Новый заказ</button>':''}
      </div>
    </div>
    <div class="card"><div id="orders-table"></div></div>`);
    renderOrdersTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderOrdersTable(){
  const {items,total,page}=paginate(ordersData,ordersPage,PAGE_SIZE);
  document.getElementById('orders-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Дата</th><th>Поставщик</th><th>Магазин</th><th>Менеджер</th><th>Сумма</th><th>Статус</th><th></th></tr></thead>
      <tbody>${items.map(o=>`<tr>
        <td>${o.id}</td><td>${fmtDate(o.date)}</td>
        <td>${esc(o.supplier)}</td><td><small>${esc(o.store)}</small></td>
        <td><small>${esc(o.manager)}</small></td>
        <td><b>${fmtMoney(o.total)}</b></td>
        <td>${statusBadge(o.status)}</td>
        <td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick="viewOrder(${o.id})">Детали</button>
          <button class="btn btn-outline btn-xs" onclick="updateOrderStatus(${o.id},'${esc(o.status)}')">Статус</button>
        </td></tr>`).join('')}
      </tbody></table></div>
    ${paginationHtml(page,total,'setOrdersPage')}`;
}
function setOrdersPage(p){ordersPage=p;renderOrdersTable();}
async function viewOrder(id){
  try{
    const o=await get('/orders/'+id);
    openModal('Заказ #'+id,`
      <div class="form-row" style="margin-bottom:12px">
        <div><label>Поставщик</label><p>${esc(o.supplier)}</p></div>
        <div><label>Магазин</label><p>${esc(o.store)}</p></div>
        <div><label>Менеджер</label><p>${esc(o.manager)}</p></div>
        <div><label>Дата</label><p>${fmtDate(o.date)}</p></div>
        <div><label>Статус</label><p>${statusBadge(o.status)}</p></div>
        <div><label>Сумма</label><p><b>${fmtMoney(o.total)}</b></p></div>
      </div>
      <hr class="separator">
      <div class="card-title" style="font-size:15px">Состав заказа</div>
      <div class="items-list">${(o.items||[]).map(i=>`
        <div class="item-row"><span>${esc(i.name)}</span>
        <span>${i.qty} шт × ${fmtMoney(i.price)}</span></div>`).join('')}
      </div>`,'<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}
function updateOrderStatus(id,cur){
  openModal('Статус заказа #'+id,`
    <div class="form-group"><label>Новый статус</label>
      <select id="os-status">${['В обработке','В пути','Доставлен','ожидается','Отменен'].map(s=>`<option ${s===cur?'selected':''}>${s}</option>`).join('')}</select></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveOrderStatus(${id})">Сохранить</button>`);
}
async function saveOrderStatus(id){
  try{await put('/orders/'+id+'/status',{status:document.getElementById('os-status').value});closeModal();pgOrders();}
  catch(e){alert(e.message);}
}

// Новый заказ — магазин менеджера подставляется автоматически
let orderCartItems=[];
async function modalNewOrder(){
  try{
    const [products,suppliers,stores]=await Promise.all([
      get('/products'),get('/suppliers'),
      ROLE==='ADMIN'?get('/stores'):Promise.resolve(MY_STORE?[MY_STORE]:[])]);
    const prodOpts=products.map(p=>`<option value="${p.article}" data-price="${p.price}" data-name="${esc(p.name)}">${esc(p.name)} [${p.article}] — ${fmtMoney(p.price)}</option>`).join('');
    const suppOpts=suppliers.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('');
    orderCartItems=[];
    const storeFixed=MY_STORE&&ROLE==='MANAGER';
    openModal('Новый заказ поставщику',`
      <div class="form-row">
        <div class="form-group"><label>Поставщик</label>
          <select id="no-supp"><option value="">— Выберите —</option>${suppOpts}</select></div>
        <div class="form-group"><label>Магазин</label>
          ${storeFixed
            ?`<input type="text" value="${esc(MY_STORE.address)}" readonly style="background:var(--cream)">
               <input type="hidden" id="no-store" value="${MY_STORE.id}">`
            :`<select id="no-store">${stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('')}</select>`}
        </div>
      </div>
      <hr class="separator">
      <div class="form-row">
        <div class="form-group"><label>Товар</label>
          <select id="no-product"><option value="">— Выберите —</option>${prodOpts}</select></div>
        <div class="form-group"><label>Кол-во</label>
          <input type="number" id="no-qty" value="1" min="1" style="width:80px"></div>
      </div>
      <button class="btn btn-outline btn-sm" onclick="noAddItem()">+ Добавить</button>
      <div id="no-cart" style="margin-top:12px"></div>
      <div id="no-total" style="font-weight:600;margin-top:8px"></div>`,
      `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
       <button class="btn btn-primary" onclick="noSubmit()">Создать заказ</button>`);
    renderNoCart();
  }catch(e){alert(e.message);}
}
function noAddItem(){
  const sel=document.getElementById('no-product');const opt=sel.options[sel.selectedIndex];
  if(!opt||!opt.value)return;
  const qty=parseInt(document.getElementById('no-qty').value)||1;
  const art=parseInt(opt.value),price=parseInt(opt.dataset.price),name=opt.dataset.name;
  const ex=orderCartItems.find(i=>i.article===art);
  if(ex)ex.qty+=qty;else orderCartItems.push({article:art,name,price,qty});
  renderNoCart();
}
function noRemoveItem(idx){orderCartItems.splice(idx,1);renderNoCart();}
function renderNoCart(){
  const el=document.getElementById('no-cart');if(!el)return;
  el.innerHTML=`<div class="items-list">${orderCartItems.map((i,idx)=>`
    <div class="item-row"><span>${esc(i.name)} × ${i.qty}</span>
    <span>${fmtMoney(i.price*i.qty)}<span class="item-row-del" onclick="noRemoveItem(${idx})">✕</span></span></div>`).join('')
    ||'<p style="color:var(--smoke);font-size:13px">Нет позиций</p>'}</div>`;
  const tot=document.getElementById('no-total');
  if(tot)tot.textContent=orderCartItems.length?'Итого: '+fmtMoney(orderCartItems.reduce((s,i)=>s+i.price*i.qty,0)):'';
}
async function noSubmit(){
  const suppId=parseInt(document.getElementById('no-supp').value);
  const storeId=parseInt(document.getElementById('no-store').value);
  if(!suppId)return alert('Выберите поставщика');
  if(!orderCartItems.length)return alert('Добавьте товары');
  try{
    await post('/orders',{store_id:storeId,supplier_id:suppId,
      items:orderCartItems.map(i=>({article:i.article,qty:i.qty}))});
    closeModal();pgOrders();
  }catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// SUPPLIERS / STORES / REVIEWS
// ═══════════════════════════════════════════════════════════════
async function pgSuppliers(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/suppliers');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Поставщики</div>
      <button class="btn btn-outline btn-sm" onclick="editSupplier(null)">+ Добавить</button>
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Название</th><th>Email</th><th>Телефон</th><th>Заказов</th><th></th></tr></thead>
        <tbody>${data.map(s=>`<tr>
          <td><b>${esc(s.name)}</b></td><td>${esc(s.email)}</td><td>${esc(s.phone)}</td>
          <td><span class="badge badge-info">${s.order_count}</span></td>
          <td class="td-actions">
            <button class="btn btn-ghost btn-xs" onclick="editSupplier(${s.id},'${esc(s.name)}','${esc(s.email)}','${esc(s.phone)}')">✏</button>
            <button class="btn btn-danger btn-xs" onclick="deleteSupplier(${s.id})">🗑</button>
          </td></tr>`).join('')}
        </tbody></table></div></div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function editSupplier(id,name='',email='',phone=''){
  openModal(id?'Редактировать':'Новый поставщик',`
    <div class="form-group"><label>Название</label><input id="es-name" value="${esc(name)}"></div>
    <div class="form-group"><label>Email</label><input id="es-email" type="email" value="${esc(email)}"></div>
    <div class="form-group"><label>Телефон</label><input id="es-phone" value="${esc(phone)}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveSupplier(${id||0})">Сохранить</button>`);
}
async function saveSupplier(id){
  const name=document.getElementById('es-name').value;
  const email=document.getElementById('es-email').value;
  const phone=document.getElementById('es-phone').value;
  if(!name||!email||!phone)return alert('Заполните все поля');
  try{
    if(id) await put('/suppliers/'+id,{name,email,phone});
    else   await post('/suppliers',{name,email,phone});
    closeModal();pgSuppliers();
  }catch(e){alert(e.message);}
}
async function deleteSupplier(id){
  if(!confirm('Удалить?'))return;
  try{await del('/suppliers/'+id);pgSuppliers();}catch(e){alert(e.message);}
}

async function pgStores(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const stores=await get('/stores');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Магазины сети</div>
      <button class="btn btn-outline btn-sm" onclick="editStore(null)">+ Добавить магазин</button>
    </div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px">
      ${stores.map(s=>`
      <div class="card" style="margin-bottom:0">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:10px">
          <div>
            <div style="font-family:'Cormorant Garamond',serif;font-size:17px">🏪 ${esc(s.address)}</div>
            <div style="font-size:12px;color:var(--smoke);margin-top:2px">${esc(s.phone)}</div>
          </div>
          <div class="td-actions">
            <button class="btn btn-ghost btn-xs" onclick="editStore(${s.id},'${esc(s.address)}','${esc(s.phone)}')">✏</button>
            <button class="btn btn-danger btn-xs" onclick="deleteStore(${s.id})">🗑</button>
          </div>
        </div>
        <div style="font-size:12px;color:var(--ash)">👤 <b>${esc(s.manager||'—')}</b></div>
        <div style="margin-top:10px;display:flex;gap:6px">
          <button class="btn btn-ghost btn-xs" onclick="pgStock('${s.id}')">📦 Остатки</button>
          <button class="btn btn-ghost btn-xs" onclick="pgSales('','','${s.id}')">🛒 Продажи</button>
        </div>
      </div>`).join('')}</div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function editStore(id,addr='',phone=''){
  openModal(id?'Редактировать магазин':'Новый магазин',`
    <div class="form-group"><label>Адрес</label><input id="est-addr" value="${esc(addr)}"></div>
    <div class="form-group"><label>Телефон</label><input id="est-phone" value="${esc(phone)}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveStore(${id||0})">Сохранить</button>`);
}
async function saveStore(id){
  const addr=document.getElementById('est-addr').value;
  const phone=document.getElementById('est-phone').value;
  if(!addr||!phone)return alert('Заполните все поля');
  try{
    if(id)await put('/stores/'+id,{address:addr,phone});
    else  await post('/stores',{address:addr,phone});
    closeModal();pgStores();
  }catch(e){alert(e.message);}
}
async function deleteStore(id){
  if(!confirm('Удалить магазин?'))return;
  try{await del('/stores/'+id);pgStores();}catch(e){alert(e.message);}
}

async function pgReviews(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const reviews=await get('/reviews');
    const avg=reviews.length?reviews.reduce((s,r)=>s+r.rating,0)/reviews.length:0;
    setPage(`
    <div id="page-alert"></div>
    <div class="stats-grid" style="grid-template-columns:repeat(3,1fr)">
      <div class="stat-card"><div class="stat-value">${reviews.length}</div><div class="stat-label">Всего отзывов</div></div>
      <div class="stat-card"><div class="stat-value">${avg.toFixed(1)} ★</div><div class="stat-label">Средний рейтинг</div></div>
      <div class="stat-card"><div class="stat-value">${reviews.filter(r=>r.rating>=4).length}</div><div class="stat-label">Положительных</div></div>
    </div>
    <div class="section-header" style="margin-top:16px">
      <div class="section-title">Отзывы клиентов</div>
      ${ROLE==='CLIENT'?`<button class="btn btn-outline btn-sm" onclick="modalAddReview()">+ Оставить отзыв</button>`:''}
    </div>
    <div style="display:flex;flex-direction:column;gap:12px">
      ${reviews.map(r=>`
      <div class="card" style="margin-bottom:0;padding:16px 20px">
        <div style="display:flex;justify-content:space-between;align-items:flex-start">
          <div>
            <div style="font-weight:500">${esc(r.client||'Аноним')}</div>
            <div style="font-size:11px;color:var(--smoke);margin-top:2px">
              🏪 ${esc(r.store||'Магазин не указан')}
            </div>
            <div class="stars" style="margin-top:4px">${stars(r.rating)}</div>
          </div>
          <div style="display:flex;align-items:center;gap:8px">
            <span style="font-size:12px;color:var(--smoke)">${fmtDate(r.date)}</span>
            ${ROLE==='ADMIN'?`<button class="btn btn-danger btn-xs" onclick="deleteReview(${r.id})">🗑</button>`:''}
          </div>
        </div>
        ${r.comment?`<div style="margin-top:10px;font-size:13px;color:var(--charcoal);line-height:1.6;border-left:2px solid var(--gold-light);padding-left:10px">${esc(r.comment)}</div>`:''}
      </div>`).join('')||'<div class="empty-state"><div class="esi">⭐</div><p>Отзывов пока нет</p></div>'}
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalAddReview(){
  openModal('Оставить отзыв',`
    <div class="form-group"><label>Рейтинг</label>
      <select id="rv-rating">
        <option value="5">★★★★★ Отлично</option><option value="4">★★★★☆ Хорошо</option>
        <option value="3">★★★☆☆ Средне</option><option value="2">★★☆☆☆ Плохо</option>
        <option value="1">★☆☆☆☆ Ужасно</option>
      </select></div>
    <div class="form-group"><label>Комментарий</label>
      <textarea id="rv-comment" placeholder="Поделитесь впечатлениями..."></textarea></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="submitReview()">Отправить</button>`);
}
async function submitReview(){
  const rating=parseInt(document.getElementById('rv-rating').value);
  const comment=document.getElementById('rv-comment').value;
  const clientId=parseInt(REF);
  if(!clientId)return alert('Ошибка: не определён клиент');
  try{await post('/reviews',{client_id:clientId,rating,comment});closeModal();pgReviews();}
  catch(e){alert(e.message);}
}
async function deleteReview(id){
  if(!confirm('Удалить отзыв?'))return;
  try{await del('/reviews/'+id);pgReviews();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// CLIENT CATALOG / MY PURCHASES
// ═══════════════════════════════════════════════════════════════
async function pgCatalog(cat='',srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const products=await get('/products',{category:cat,search:srch});
    const cats=[...new Set(products.map(p=>p.category))].sort();
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="padding:14px 20px;margin-bottom:0">
      <div class="filters">
        <div class="filter-group"><label>Категория</label>
          <select id="cc-cat" onchange="pgCatalog(this.value,document.getElementById('cc-srch').value)">
            <option value="">Все категории</option>
            ${cats.map(c=>`<option ${c===cat?'selected':''}>${esc(c)}</option>`).join('')}
          </select></div>
        <div class="filter-group"><label>Поиск</label>
          <input id="cc-srch" type="text" placeholder="Название" value="${esc(srch)}"></div>
        <button class="btn btn-primary btn-sm" onclick="pgCatalog(document.getElementById('cc-cat').value,document.getElementById('cc-srch').value)">Найти</button>
      </div>
    </div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:14px;margin-top:14px">
      ${products.map(p=>{
        const icon={'Кольца':'💍','Серьги':'💎','Браслеты':'✨','Подвески':'🔮','Цепочки':'⛓️','Часы':'⌚','Броши':'🌸'}[p.category]||'💎';
        return`<div class="card" style="margin-bottom:0;padding:16px;cursor:pointer;transition:box-shadow .2s"
          onclick="viewProductDetail(${p.article})"
          onmouseover="this.style.boxShadow='0 4px 20px rgba(201,168,76,.25)'"
          onmouseout="this.style.boxShadow=''">
          <div style="text-align:center;font-size:36px;margin-bottom:8px">${icon}</div>
          <div style="font-size:14px;font-weight:500;margin-bottom:4px;text-align:center">${esc(p.name)}</div>
          <div style="text-align:center;margin-bottom:6px"><span class="badge badge-gold">${esc(p.category)}</span></div>
          <div style="text-align:center;font-family:'Cormorant Garamond',serif;font-size:20px;color:var(--gold)">${fmtMoney(p.price)}</div>
          <div style="text-align:center;margin-top:6px;font-size:11px;color:var(--smoke)">Нажмите для деталей</div>
        </div>`;}).join('')||'<div class="empty-state"><div class="esi">🔍</div><p>Ничего не найдено</p></div>'}
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

async function pgMyPurchases(fromVal='',toVal=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const clientId=parseInt(REF);
    if(!clientId)return setPage('<div class="alert alert-err">Ошибка идентификации клиента</div>');
    const [sales,client]=await Promise.all([
      get('/clients/'+clientId+'/sales',{from:fromVal,to:toVal}),
      get('/clients/'+clientId)]);
    const totalSpent=sales.reduce((s,x)=>s+(x.total||0),0);
    setPage(`
    <div id="page-alert"></div>
    <div class="stats-grid" style="grid-template-columns:repeat(3,1fr)">
      <div class="stat-card"><div class="stat-value">${sales.length}</div><div class="stat-label">Покупок</div></div>
      <div class="stat-card"><div class="stat-value">${fmtMoney(totalSpent)}</div><div class="stat-label">Потрачено</div></div>
      <div class="stat-card"><div class="stat-value">${sales.length?fmtMoney(totalSpent/sales.length):'—'}</div><div class="stat-label">Средний чек</div></div>
    </div>
    <div class="card" style="padding:14px 20px;margin-bottom:0">
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="mp-from" value="${fromVal}"></div>
        <div class="filter-group"><label>По</label><input type="date" id="mp-to" value="${toVal}"></div>
        <button class="btn btn-primary btn-sm" onclick="pgMyPurchases(document.getElementById('mp-from').value,document.getElementById('mp-to').value)">Применить</button>
      </div>
    </div>
    <div class="card">
      ${sales.length?`<div class="tbl-wrap"><table>
        <thead><tr><th>Дата</th><th>Магазин</th><th>Товары</th><th>Оплата</th><th>Сумма</th></tr></thead>
        <tbody>${sales.map(s=>`<tr>
          <td>${fmtDate(s.date)}</td><td><small>${esc(s.store)}</small></td>
          <td style="max-width:200px;white-space:normal;font-size:12px">${esc(s.products.replace(/[{}]/g,''))}</td>
          <td>${esc(s.payment)}</td><td><b>${fmtMoney(s.total)}</b></td></tr>`).join('')}
        </tbody></table></div>`
        :'<div class="empty-state"><div class="esi">🛍️</div><p>Покупок пока нет</p></div>'}
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
JS3_EOF
ok "app.js part 3 (orders, suppliers, stores, reviews, catalog)"


cat >> "$PROJ/frontend/js/app.js" << 'JS4_EOF'

// ═══════════════════════════════════════════════════════════════
// REPORTS — менеджер видит только свой магазин
//            админ выбирает магазин или всю сеть
// ═══════════════════════════════════════════════════════════════
async function pgReports(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const stores=ROLE==='ADMIN'?await get('/stores'):[];
    const storeLabel=MY_STORE?' ('+MY_STORE.address.split(',').slice(-1)[0].trim()+')':'';
    const reportCards=[
      {id:'cat',   icon:'📊', title:'Продажи по категориям',  desc:'Выручка и кол-во по категориям за период'},
      {id:'stock', icon:'📦', title:'Остатки в магазине',      desc:'Позиции ниже порогового остатка'},
      {id:'orders',icon:'📋', title:'Заказы поставщикам',      desc:'Статус и сумма заказов за период'},
      {id:'revenue',icon:'💰',title:'Выручка'+storeLabel,      desc:'Выручка, транзакции, средний чек'},
      {id:'top',   icon:'🏆', title:'Топ клиентов',            desc:'Рейтинг клиентов по объёму покупок'},
    ];
    setPage(`
    <div id="page-alert"></div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:14px;margin-bottom:20px">
      ${reportCards.map(rc=>`
      <div class="card" style="margin-bottom:0;cursor:pointer;transition:box-shadow .2s"
        onclick="showReport('${rc.id}')"
        onmouseover="this.style.boxShadow='0 4px 20px rgba(201,168,76,.2)'"
        onmouseout="this.style.boxShadow=''">
        <div style="font-size:32px;margin-bottom:10px">${rc.icon}</div>
        <div class="card-title" style="font-size:16px">${rc.title}</div>
        <div style="font-size:12px;color:var(--smoke)">${rc.desc}</div>
      </div>`).join('')}
    </div>
    <div id="report-result"></div>`);

    // Сохраним stores в замыкании через window
    window._reportStores=stores;
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// Строит строку с выбором магазина/сети (только для ADMIN)
function storeFilterHtml(fieldId,label='Магазин'){
  const stores=window._reportStores||[];
  if(ROLE!=='ADMIN') return '';
  return`<div class="filter-group"><label>${label}</label>
    <select id="${fieldId}">
      <option value="">Вся сеть</option>
      ${stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('')}
    </select></div>`;
}
function getStoreParam(fieldId){
  if(ROLE==='MANAGER') return MY_STORE?MY_STORE.id:'';
  const el=document.getElementById(fieldId);
  return el?el.value:'';
}

async function showReport(type){
  const el=document.getElementById('report-result');
  if(!el)return;
  const cats=['','Кольца','Серьги','Браслеты','Подвески','Цепочки','Часы','Броши'];
  const payments=['','Карта','Наличные'];
  const statuses=['','В обработке','В пути','Доставлен','ожидается','Отменен'];
  const suppliers=type==='orders'?await get('/suppliers').catch(()=>[]):[];

  if(type==='cat'){
    el.innerHTML=`<div class="card">
      <div class="card-title">📊 Продажи по категориям</div>
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="rc-from" value="2024-01-01"></div>
        <div class="filter-group"><label>По</label><input type="date" id="rc-to" value="2099-12-31"></div>
        <div class="filter-group"><label>Категория</label>
          <select id="rc-cat">${cats.map(c=>`<option value="${c}">${c||'Все'}</option>`).join('')}</select></div>
        ${storeFilterHtml('rc-store')}
        <button class="btn btn-primary btn-sm" onclick="runReportCat()">Сформировать</button>
      </div>
      <div id="rc-result"></div></div>`;
  }
  else if(type==='stock'){
    const stores=window._reportStores||[];
    const storeOpts=ROLE==='ADMIN'
      ?`<select id="rs-store">${stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('')}</select>`
      :`<input type="text" value="${esc(MY_STORE?MY_STORE.address:'—')}" readonly style="background:var(--cream);max-width:300px">
        <input type="hidden" id="rs-store" value="${MY_STORE?MY_STORE.id:''}">`;
    el.innerHTML=`<div class="card">
      <div class="card-title">📦 Остатки в магазине</div>
      <div class="filters">
        <div class="filter-group"><label>Магазин</label>${storeOpts}</div>
        <div class="filter-group"><label>Порог ≤</label>
          <input type="number" id="rs-thresh" value="5" style="width:80px"></div>
        <button class="btn btn-primary btn-sm" onclick="runReportStock()">Сформировать</button>
      </div>
      <div id="rs-result"></div></div>`;
  }
  else if(type==='orders'){
    el.innerHTML=`<div class="card">
      <div class="card-title">📋 Заказы поставщикам</div>
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="ro-from" value="2024-01-01"></div>
        <div class="filter-group"><label>По</label><input type="date" id="ro-to" value="2099-12-31"></div>
        <div class="filter-group"><label>Поставщик</label>
          <select id="ro-supp"><option value="">Все</option>
            ${suppliers.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('')}</select></div>
        <div class="filter-group"><label>Статус</label>
          <select id="ro-status">${statuses.map(s=>`<option value="${s}">${s||'Все'}</option>`).join('')}</select></div>
        ${storeFilterHtml('ro-store')}
        <button class="btn btn-primary btn-sm" onclick="runReportOrders()">Сформировать</button>
      </div>
      <div id="ro-result"></div></div>`;
  }
  else if(type==='revenue'){
    el.innerHTML=`<div class="card">
      <div class="card-title">💰 Выручка по магазинам</div>
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="rr-from" value="2024-01-01"></div>
        <div class="filter-group"><label>По</label><input type="date" id="rr-to" value="2099-12-31"></div>
        <div class="filter-group"><label>Оплата</label>
          <select id="rr-pay">${payments.map(p=>`<option value="${p}">${p||'Все способы'}</option>`).join('')}</select></div>
        ${storeFilterHtml('rr-store')}
        <button class="btn btn-primary btn-sm" onclick="runReportRevenue()">Сформировать</button>
      </div>
      <div id="rr-result"></div></div>`;
  }
  else if(type==='top'){
    el.innerHTML=`<div class="card">
      <div class="card-title">🏆 Топ клиентов</div>
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="rt-from" value="2024-01-01"></div>
        <div class="filter-group"><label>По</label><input type="date" id="rt-to" value="2099-12-31"></div>
        <div class="filter-group"><label>Топ N</label>
          <input type="number" id="rt-lim" value="10" min="1" max="100" style="width:80px"></div>
        ${storeFilterHtml('rt-store')}
        <button class="btn btn-primary btn-sm" onclick="runReportTop()">Сформировать</button>
      </div>
      <div id="rt-result"></div></div>`;
  }
  el.scrollIntoView({behavior:'smooth',block:'start'});
}

async function runReportCat(){
  const from=document.getElementById('rc-from').value;
  const to=document.getElementById('rc-to').value;
  const cat=document.getElementById('rc-cat').value;
  const storeId=getStoreParam('rc-store');
  const el=document.getElementById('rc-result');
  el.innerHTML='<div style="padding:20px;text-align:center;color:var(--smoke)">⏳ Загрузка...</div>';
  try{
    const data=await get('/reports/sales-by-category',{from,to,category:cat,store_id:storeId});
    if(!data.length){el.innerHTML='<div class="empty-state"><div class="esi">📊</div><p>Нет данных за период</p></div>';return;}
    const maxRev=Math.max(...data.map(d=>d.revenue));
    el.innerHTML=`<hr class="separator">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Категория</th><th>Кол-во, шт.</th><th>Выручка</th><th>Доля в обороте</th></tr></thead>
        <tbody>${data.map(d=>`<tr>
          <td><span class="badge badge-gold">${esc(d.category)}</span></td>
          <td>${fmt(d.qty)}</td><td><b>${fmtMoney(d.revenue)}</b></td>
          <td><div style="display:flex;align-items:center;gap:8px">
            <div style="flex:1;background:#f0ebe0;border-radius:2px;height:12px;overflow:hidden">
              <div style="width:${d.pct}%;height:100%;background:linear-gradient(90deg,var(--gold-dark),var(--gold))"></div>
            </div>
            <span style="font-size:12px;font-weight:500;width:42px">${d.pct}%</span>
          </div></td></tr>`).join('')}
        </tbody></table></div>
      <hr class="separator">
      <div class="card-title" style="font-size:15px">Диаграмма</div>
      <div class="chart-bar-wrap">${data.map(d=>`
        <div class="chart-bar-row">
          <div class="chart-bar-label">${esc(d.category)}</div>
          <div class="chart-bar-track"><div class="chart-bar-fill" style="width:${Math.round(d.revenue/maxRev*100)}%">${fmtMoney(d.revenue)}</div></div>
          <div class="chart-bar-val">${d.pct}%</div>
        </div>`).join('')}</div>`;
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}

async function runReportStock(){
  const storeId=document.getElementById('rs-store').value;
  const thresh=document.getElementById('rs-thresh').value;
  const el=document.getElementById('rs-result');
  el.innerHTML='<div style="padding:20px;text-align:center;color:var(--smoke)">⏳ Загрузка...</div>';
  if(!storeId){el.innerHTML='<div class="alert alert-err">Выберите магазин</div>';return;}
  try{
    const data=await get('/reports/stock-status',{store_id:storeId,threshold:thresh});
    if(!data.length){el.innerHTML=`<div class="empty-state"><div class="esi">📦</div><p>Нет позиций с остатком ≤ ${thresh}</p></div>`;return;}
    const maxQ=Math.max(...data.map(d=>d.qty),1);
    el.innerHTML=`<hr class="separator">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th><th>Остаток</th><th>Статус</th></tr></thead>
        <tbody>${data.map(d=>{
          const lvl=d.qty<=0?'danger':d.qty<=2?'warning':'success';
          const lbl=d.qty<=0?'Нет':'Критический';
          return`<tr>
            <td><code>${d.article}</code></td><td>${esc(d.name)}</td>
            <td><span class="badge badge-gold">${esc(d.category)}</span></td>
            <td>${fmtMoney(d.price)}</td>
            <td><b style="color:var(--${lvl==='danger'?'danger':lvl==='warning'?'warning':'success'})">${d.qty}</b></td>
            <td><span class="badge badge-${lvl}">${lbl}</span></td>
          </tr>`;}).join('')}
        </tbody></table></div>
      <hr class="separator">
      <div class="chart-bar-wrap">${data.slice(0,10).map(d=>{
        const clr=d.qty<=0?'var(--danger)':d.qty<=2?'var(--warning)':'';
        return`<div class="chart-bar-row">
          <div class="chart-bar-label">${esc(d.name.substring(0,18))}</div>
          <div class="chart-bar-track"><div class="chart-bar-fill" style="width:${Math.round(d.qty/maxQ*100)}%;${clr?'background:'+clr:''}">${d.qty}</div></div>
          <div class="chart-bar-val">${d.qty} шт</div></div>`;}).join('')}</div>`;
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}

async function runReportOrders(){
  const from=document.getElementById('ro-from').value;
  const to=document.getElementById('ro-to').value;
  const supp=document.getElementById('ro-supp').value;
  const status=document.getElementById('ro-status').value;
  const storeId=getStoreParam('ro-store');
  const el=document.getElementById('ro-result');
  el.innerHTML='<div style="padding:20px;text-align:center;color:var(--smoke)">⏳ Загрузка...</div>';
  try{
    const data=await get('/reports/orders',{from,to,supplier_id:supp,status,store_id:storeId});
    const total=data.reduce((s,d)=>s+(d.total||0),0);
    el.innerHTML=`<hr class="separator">
      <div class="stats-grid" style="grid-template-columns:repeat(3,1fr);margin-bottom:14px">
        <div class="stat-card"><div class="stat-value">${data.length}</div><div class="stat-label">Заказов</div></div>
        <div class="stat-card"><div class="stat-value">${fmtMoney(total)}</div><div class="stat-label">Сумма</div></div>
        <div class="stat-card"><div class="stat-value">${data.length?fmtMoney(total/data.length):'—'}</div><div class="stat-label">Средний</div></div>
      </div>
      <div class="tbl-wrap"><table>
        <thead><tr><th>#</th><th>Дата</th><th>Поставщик</th><th>Магазин</th><th>Менеджер</th><th>Сумма</th><th>Статус</th></tr></thead>
        <tbody>${data.map(d=>`<tr>
          <td>${d.id}</td><td>${fmtDate(d.date)}</td><td>${esc(d.supplier)}</td>
          <td><small>${esc(d.store)}</small></td><td><small>${esc(d.manager)}</small></td>
          <td><b>${fmtMoney(d.total)}</b></td><td>${statusBadge(d.status)}</td>
        </tr>`).join('')||'<tr><td colspan="7" style="text-align:center;color:var(--smoke)">Нет данных</td></tr>'}
        </tbody></table></div>`;
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}

async function runReportRevenue(){
  const from=document.getElementById('rr-from').value;
  const to=document.getElementById('rr-to').value;
  const pay=document.getElementById('rr-pay').value;
  const storeId=getStoreParam('rr-store');
  const el=document.getElementById('rr-result');
  el.innerHTML='<div style="padding:20px;text-align:center;color:var(--smoke)">⏳ Загрузка...</div>';
  try{
    const data=await get('/reports/revenue-by-store',{from,to,payment:pay,store_id:storeId});
    if(!data.length){el.innerHTML='<div class="empty-state"><div class="esi">💰</div><p>Нет данных</p></div>';return;}
    const maxRev=Math.max(...data.map(d=>d.revenue));
    el.innerHTML=`<hr class="separator">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Магазин</th><th>Выручка</th><th>Транзакций</th><th>Средний чек</th></tr></thead>
        <tbody>${data.map(d=>`<tr>
          <td>${esc(d.store)}</td><td><b>${fmtMoney(d.revenue)}</b></td>
          <td>${fmt(d.tx_count)}</td><td>${fmtMoney(d.avg_check)}</td>
        </tr>`).join('')}</tbody></table></div>
      <hr class="separator">
      <div class="card-title" style="font-size:15px">Сравнение выручки</div>
      <div class="chart-bar-wrap">${data.map(d=>`
        <div class="chart-bar-row">
          <div class="chart-bar-label">${esc(d.store.split(',').slice(-1)[0]||d.store)}</div>
          <div class="chart-bar-track"><div class="chart-bar-fill" style="width:${Math.round(d.revenue/maxRev*100)}%">${fmtMoney(d.revenue)}</div></div>
          <div class="chart-bar-val">${fmt(d.tx_count)} прод.</div>
        </div>`).join('')}</div>`;
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}

async function runReportTop(){
  const from=document.getElementById('rt-from').value;
  const to=document.getElementById('rt-to').value;
  const lim=document.getElementById('rt-lim').value;
  const storeId=getStoreParam('rt-store');
  const el=document.getElementById('rt-result');
  el.innerHTML='<div style="padding:20px;text-align:center;color:var(--smoke)">⏳ Загрузка...</div>';
  try{
    const data=await get('/reports/top-customers',{from,to,limit:lim,store_id:storeId});
    if(!data.length){el.innerHTML='<div class="empty-state"><div class="esi">🏆</div><p>Нет данных</p></div>';return;}
    const maxTotal=Math.max(...data.map(d=>d.total));
    el.innerHTML=`<hr class="separator">
      <div class="tbl-wrap"><table>
        <thead><tr><th>#</th><th>ФИО</th><th>Телефон</th><th>Магазин</th><th>Предпочт. категория</th><th>Покупок</th><th>Сумма</th><th>Ср. чек</th></tr></thead>
        <tbody>${data.map((d,i)=>`<tr>
          <td><b style="color:var(--gold)">${i+1}</b></td>
          <td>${esc(d.fio||'—')}</td><td>${esc(d.phone)}</td>
          <td><small>${esc(d.top_store||'—')}</small></td>
          <td><span class="badge badge-gold">${esc(d.top_category||'—')}</span></td>
          <td>${fmt(d.count)}</td><td><b>${fmtMoney(d.total)}</b></td>
          <td>${fmtMoney(d.avg)}</td>
        </tr>`).join('')}</tbody></table></div>
      <hr class="separator">
      <div class="chart-bar-wrap">${data.map(d=>`
        <div class="chart-bar-row">
          <div class="chart-bar-label">${esc((d.fio||'—').split(' ')[0])}</div>
          <div class="chart-bar-track"><div class="chart-bar-fill" style="width:${Math.round(d.total/maxTotal*100)}%">${fmtMoney(d.total)}</div></div>
          <div class="chart-bar-val">${fmt(d.count)} поk.</div>
        </div>`).join('')}</div>`;
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}

// ── Init ─────────────────────────────────────────────────────
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeModal();});
document.getElementById('au-pass').addEventListener('keydown',e=>{if(e.key==='Enter')doLogin();});
tryAutoLogin();
JS4_EOF
ok "app.js part 4 (reports with store filter + top customers with store/category)"


# ═══════════════════════════════════════════════════════════════
# 7. ReportController — store_id фильтр во всех отчётах
#    top-customers: + top_store, top_category
# ═══════════════════════════════════════════════════════════════
hdr "7. ReportController — store filter + top_store/top_category"
cat > "$CTRL/ReportController.cc" << 'EOF'
#include "ReportController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

// ── Отчёт 1: Продажи по категориям (WITH CTE, фильтр по магазину)
void ReportController::salesByCategory(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from   = req->getParameter("from");    if(from.empty())   from   ="2000-01-01";
    std::string to     = req->getParameter("to");      if(to.empty())     to     ="2099-12-31";
    std::string cat    = req->getParameter("category");
    std::string storeId= req->getParameter("store_id");
    app().getDbClient()->execSqlAsync(
        "WITH cat_sales AS ("
        "  SELECT p.product_category,"
        "         SUM(si.sale_item_quantity)                    AS total_qty,"
        "         SUM(p.product_price * si.sale_item_quantity)  AS cat_revenue "
        "  FROM SALE s "
        "  JOIN SALE_ITEM si ON s.sale_id=si.sale_id "
        "  JOIN PRODUCT p   ON si.product_article=p.product_article "
        "  WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "    AND ($3='' OR p.product_category=$3) "
        "    AND ($4='' OR s.store_id=$4::int) "
        "  GROUP BY p.product_category"
        "), total AS (SELECT SUM(cat_revenue) AS grand FROM cat_sales) "
        "SELECT cs.product_category, cs.total_qty, cs.cat_revenue,"
        "       ROUND((cs.cat_revenue::numeric/NULLIF(t.grand,0))*100,2) AS pct "
        "FROM cat_sales cs CROSS JOIN total t ORDER BY cs.cat_revenue DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["category"]=row["product_category"].as<std::string>();
                o["qty"]     =static_cast<Json::Int64>(row["total_qty"].as<long long>());
                o["revenue"] =row["cat_revenue"].as<double>();
                o["pct"]     =row["pct"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,cat,storeId);
}

// ── Отчёт 2: Остатки в магазине
void ReportController::stockStatus(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id");
    if(storeId.empty())return cb(jsonErr("store_id required"));
    std::string thresh=req->getParameter("threshold");
    if(thresh.empty())thresh="9999";
    app().getDbClient()->execSqlAsync(
        "SELECT p.product_article,p.product_name,p.product_category,p.product_price,st.stock_quantity "
        "FROM STOCK st JOIN PRODUCT p ON st.product_article=p.product_article "
        "WHERE st.store_id=$1::int AND st.stock_quantity<=$2::int "
        "ORDER BY st.stock_quantity ASC,p.product_name",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["article"] =row["product_article"].as<int>();
                o["name"]    =row["product_name"].as<std::string>();
                o["category"]=row["product_category"].as<std::string>();
                o["price"]   =row["product_price"].as<int>();
                o["qty"]     =row["stock_quantity"].as<int>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,thresh);
}

// ── Отчёт 3: Заказы поставщикам (фильтр по магазину)
void ReportController::ordersBySupplier(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    std::string suppId =req->getParameter("supplier_id");
    std::string status =req->getParameter("status");
    std::string from   =req->getParameter("from");    if(from.empty())  from  ="2000-01-01";
    std::string to     =req->getParameter("to");      if(to.empty())    to    ="2099-12-31";
    std::string storeId=req->getParameter("store_id");
    app().getDbClient()->execSqlAsync(
        "SELECT o.order_id,o.order_date,o.order_status,o.order_total,"
        "       sp.supplier_name,s.store_address,m.manager_fio "
        "FROM \"ORDER\" o "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN STORE s     ON o.store_id=s.store_id "
        "JOIN MANAGER m   ON o.manager_snils=m.manager_snils "
        "WHERE ($1='' OR o.supplier_id=$1::int) "
        "  AND ($2='' OR o.order_status=$2) "
        "  AND o.order_date BETWEEN $3::date AND $4::date "
        "  AND ($5='' OR o.store_id=$5::int) "
        "ORDER BY o.order_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]      =row["order_id"].as<int>();
                o["date"]    =row["order_date"].as<std::string>();
                o["status"]  =row["order_status"].as<std::string>();
                o["total"]   =static_cast<Json::Int64>(row["order_total"].as<long long>());
                o["supplier"]=row["supplier_name"].as<std::string>();
                o["store"]   =row["store_address"].as<std::string>();
                o["manager"] =row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        suppId,status,from,to,storeId);
}

// ── Отчёт 4: Выручка по магазинам (фильтр по одному магазину)
void ReportController::revenueByStore(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from   =req->getParameter("from");    if(from.empty())  from  ="2000-01-01";
    std::string to     =req->getParameter("to");      if(to.empty())    to    ="2099-12-31";
    std::string payment=req->getParameter("payment");
    std::string storeId=req->getParameter("store_id");
    app().getDbClient()->execSqlAsync(
        "SELECT st.store_id,st.store_address,"
        "       SUM(s.sale_total)                        AS total_revenue,"
        "       COUNT(*)                                 AS tx_count,"
        "       ROUND(AVG(s.sale_total)::numeric,2)      AS avg_check "
        "FROM SALE s JOIN STORE st ON s.store_id=st.store_id "
        "WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "  AND ($3='' OR s.sale_payment_method=$3) "
        "  AND ($4='' OR s.store_id=$4::int) "
        "GROUP BY st.store_id,st.store_address ORDER BY total_revenue DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["store_id"] =row["store_id"].as<int>();
                o["store"]    =row["store_address"].as<std::string>();
                o["revenue"]  =row["total_revenue"].as<double>();
                o["tx_count"] =static_cast<Json::Int64>(row["tx_count"].as<long long>());
                o["avg_check"]=row["avg_check"].as<double>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,payment,storeId);
}

// ── Отчёт 5: Топ клиентов — + магазин и любимая категория
void ReportController::topCustomers(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    std::string from   =req->getParameter("from");   if(from.empty())  from  ="2000-01-01";
    std::string to     =req->getParameter("to");     if(to.empty())    to    ="2099-12-31";
    std::string lim    =req->getParameter("limit");  if(lim.empty())   lim   ="10";
    std::string storeId=req->getParameter("store_id");
    app().getDbClient()->execSqlAsync(
        "WITH base AS ("
        "  SELECT s.client_id,"
        "         COUNT(s.sale_id)              AS purchase_count,"
        "         SUM(s.sale_total)             AS total_amount,"
        "         ROUND(AVG(s.sale_total)::numeric,2) AS avg_check "
        "  FROM SALE s "
        "  WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "    AND ($4='' OR s.store_id=$4::int) "
        "  GROUP BY s.client_id"
        "),"
        "top_store AS ("
        "  SELECT s.client_id,"
        "         st.store_address,"
        "         ROW_NUMBER() OVER (PARTITION BY s.client_id ORDER BY COUNT(*) DESC) AS rn "
        "  FROM SALE s JOIN STORE st ON s.store_id=st.store_id "
        "  WHERE s.sale_date BETWEEN $1::date AND $2::date "
        "    AND ($4='' OR s.store_id=$4::int) "
        "  GROUP BY s.client_id,st.store_address"
        "),"
        "top_cat AS ("
        "  SELECT si.sale_id, p.product_category,"
        "         s2.client_id,"
        "         ROW_NUMBER() OVER (PARTITION BY s2.client_id ORDER BY COUNT(*) DESC) AS rn "
        "  FROM SALE_ITEM si "
        "  JOIN PRODUCT p  ON si.product_article=p.product_article "
        "  JOIN SALE s2    ON si.sale_id=s2.sale_id "
        "  WHERE s2.sale_date BETWEEN $1::date AND $2::date "
        "    AND ($4='' OR s2.store_id=$4::int) "
        "  GROUP BY s2.client_id,p.product_category,si.sale_id"
        ") "
        "SELECT c.client_fio,c.client_phone,"
        "       b.purchase_count,b.total_amount,b.avg_check,"
        "       ts.store_address AS top_store,"
        "       tc.product_category AS top_category "
        "FROM base b "
        "JOIN CLIENT c ON b.client_id=c.client_id "
        "LEFT JOIN top_store ts ON ts.client_id=b.client_id AND ts.rn=1 "
        "LEFT JOIN top_cat   tc ON tc.client_id=b.client_id AND tc.rn=1 "
        "ORDER BY b.total_amount DESC LIMIT $3::int",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["fio"]         =row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["phone"]       =row["client_phone"].as<std::string>();
                o["count"]       =static_cast<Json::Int64>(row["purchase_count"].as<long long>());
                o["total"]       =row["total_amount"].as<double>();
                o["avg"]         =row["avg_check"].as<double>();
                o["top_store"]   =row["top_store"].isNull()?"":row["top_store"].as<std::string>();
                o["top_category"]=row["top_category"].isNull()?"":row["top_category"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        from,to,lim,storeId);
}
EOF
ok "ReportController.cc"

# ═══════════════════════════════════════════════════════════════
# 8. ClientController — фильтр по магазину для менеджера
# ═══════════════════════════════════════════════════════════════
hdr "8. ClientController — store_id filter"
cat > "$CTRL/ClientController.cc" << 'EOF'
#include "ClientController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ClientController::getAll(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb){
    std::string srch   =req->getParameter("search");
    std::string storeId=req->getParameter("store_id");
    // Если передан store_id — клиенты только этого магазина
    if(!storeId.empty()){
        app().getDbClient()->execSqlAsync(
            "SELECT DISTINCT c.client_id,c.client_fio,c.client_phone,c.client_email "
            "FROM CLIENT c "
            "JOIN SALE s ON c.client_id=s.client_id "
            "WHERE s.store_id=$1::int "
            "  AND ($2='' OR lower(c.client_fio) LIKE lower('%'||$2||'%') "
            "       OR c.client_phone LIKE '%'||$2||'%') "
            "ORDER BY c.client_fio",
            [cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(const auto& row:r){Json::Value o;
                    o["id"]   =row["client_id"].as<int>();
                    o["fio"]  =row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                    o["phone"]=row["client_phone"].as<std::string>();
                    o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
            [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            storeId,srch);
    } else {
        app().getDbClient()->execSqlAsync(
            "SELECT client_id,client_fio,client_phone,client_email FROM CLIENT "
            "WHERE $1='' OR lower(client_fio) LIKE lower('%'||$1||'%') "
            "   OR client_phone LIKE '%'||$1||'%' "
            "ORDER BY client_fio",
            [cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(const auto& row:r){Json::Value o;
                    o["id"]   =row["client_id"].as<int>();
                    o["fio"]  =row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                    o["phone"]=row["client_phone"].as<std::string>();
                    o["email"]=row["client_email"].isNull()?"":row["client_email"].as<std::string>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
            [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            srch);
    }
}

void ClientController::getOne(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT c.*,COUNT(s.sale_id) AS purchase_count,"
        "       COALESCE(SUM(s.sale_total),0) AS total_spent "
        "FROM CLIENT c LEFT JOIN SALE s ON c.client_id=s.client_id "
        "WHERE c.client_id=$1 GROUP BY c.client_id",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Клиент не найден",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["id"]            =row["client_id"].as<int>();
            o["fio"]           =row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
            o["phone"]         =row["client_phone"].as<std::string>();
            o["email"]         =row["client_email"].isNull()?"":row["client_email"].as<std::string>();
            o["purchase_count"]=row["purchase_count"].as<int>();
            o["total_spent"]   =row["total_spent"].as<double>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void ClientController::update(const HttpRequestPtr& req,
    std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string fio  =(*b)["fio"].asString();
    std::string phone=(*b)["phone"].asString();
    std::string email=(*b).get("email","").asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE CLIENT SET client_fio=$1,client_phone=$2,client_email=NULLIF($3,'') WHERE client_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);
            r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        fio,phone,email,id);
}
EOF
ok "ClientController.cc"

# ═══════════════════════════════════════════════════════════════
# 9. Финальное сообщение
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  patch_v2 полностью применён!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Изменения:"
echo -e "  ${BLUE}Бэкенд:${NC}"
echo -e "  • InfoController  — /cashiers/:snils/store, /managers/:snils/store"
echo -e "  •                   /products/:article/stock-all"
echo -e "  • ReviewController — магазин клиента в отзыве"
echo -e "  • ProductController — авто-артикул через sequence"
echo -e "  • ReportController  — store_id во всех отчётах"
echo -e "  •                     top_store + top_category в топ клиентов"
echo -e "  • ClientController  — фильтр по store_id"
echo -e "  ${BLUE}Фронтенд:${NC}"
echo -e "  • Клиент — сразу в каталог, детали товара + остатки по магазинам + размер"
echo -e "  • Кассир — поиск клиента по телефону, магазин авто, без «Безнал»"
echo -e "  • Менеджер — всё только по своему магазину, заказ с авто-магазином"
echo -e "  • Отчёты — менеджер видит только свой магазин"
echo -e "  •          админ выбирает магазин/вся сеть"
echo -e "  • Товары  — добавляют только менеджер/админ, артикул авто"
echo ""
echo -e "  ${BLUE}Запуск:${NC}"
echo -e "  docker compose down -v && docker compose up --build"
echo ""
