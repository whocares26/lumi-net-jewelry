'use strict';
// ── State ─────────────────────────────────────────────────────
let TOKEN=null,ROLE=null,REF=null,USER_ID=null;
const API='/api';
const PAGE_SIZE=20;

// ── API helper ────────────────────────────────────────────────
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
    bootApp();
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
    bootApp();
  }catch(e){showAuthErr(e.message);}
}
function showAuthErr(m){const el=document.getElementById('auth-err');el.innerHTML=`<div class="alert alert-err">${esc(m)}</div>`;}
function showRegForm(){document.getElementById('auth-login-form').style.display='none';document.getElementById('auth-reg-form').style.display='';}
function showLoginForm(){document.getElementById('auth-reg-form').style.display='none';document.getElementById('auth-login-form').style.display='';}
function logout(){TOKEN=ROLE=REF=USER_ID=null;localStorage.clear();location.reload();}

// ── Boot ──────────────────────────────────────────────────────
function bootApp(){
  document.getElementById('auth-screen').style.display='none';
  document.getElementById('app').style.display='flex';
  // Set user info
  const roleLabels={ADMIN:'Администратор',MANAGER:'Менеджер',CASHIER:'Кассир',CLIENT:'Клиент'};
  document.getElementById('ua-role').textContent=roleLabels[ROLE]||ROLE;
  document.getElementById('ua-name').textContent=
    ROLE==='CLIENT'?'Клиент #'+REF: ROLE==='CASHIER'?'Кассир':
    ROLE==='MANAGER'?'Менеджер':'Администратор';
  document.getElementById('ua-initials').textContent=(roleLabels[ROLE]||'?')[0];
  buildNav();
  navigate('dashboard');
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
            {sec:'Продажи'},
            {id:'sales',icon:'🛒',label:'Продажи'},
            {id:'clients',icon:'👤',label:'Клиенты'},
            {sec:'Каталог'},
            {id:'products',icon:'💎',label:'Товары'},
            {id:'stock',icon:'📦',label:'Остатки'},
            {sec:'Снабжение'},
            {id:'orders',icon:'📋',label:'Заказы'},
            {id:'suppliers',icon:'🏭',label:'Поставщики'},
            {sec:'Управление'},
            {id:'stores',icon:'🏪',label:'Магазины'},
            {id:'reviews',icon:'⭐',label:'Отзывы'},
            {sec:'Аналитика'},
            {id:'reports',icon:'📊',label:'Отчёты'}],
  MANAGER:[{id:'dashboard',icon:'◆',label:'Дашборд'},
            {sec:'Продажи'},
            {id:'sales',icon:'🛒',label:'Продажи'},
            {sec:'Каталог'},
            {id:'products',icon:'💎',label:'Товары'},
            {id:'stock',icon:'📦',label:'Остатки'},
            {sec:'Снабжение'},
            {id:'orders',icon:'📋',label:'Заказы'},
            {sec:'Аналитика'},
            {id:'reports',icon:'📊',label:'Отчёты'}],
  CASHIER:[{id:'dashboard',icon:'◆',label:'Дашборд'},
            {id:'sale_new',icon:'🛒',label:'Оформить продажу'},
            {id:'sales',icon:'📑',label:'История продаж'},
            {id:'products',icon:'💎',label:'Каталог товаров'},
            {id:'stock',icon:'📦',label:'Остатки'}],
  CLIENT: [{id:'dashboard',icon:'◆',label:'Главная'},
            {id:'catalog',icon:'💎',label:'Каталог'},
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
  document.querySelectorAll('.nav-item').forEach(el=>{
    el.classList.toggle('active',el.dataset.page===page);});
  const titles={dashboard:'Дашборд',sales:'Продажи',clients:'Клиенты',products:'Товары',
    stock:'Остатки на складе',orders:'Заказы поставщикам',suppliers:'Поставщики',
    stores:'Магазины',reviews:'Отзывы',reports:'Отчёты',sale_new:'Оформить продажу',
    catalog:'Каталог товаров',my_purchases:'Мои покупки'};
  document.getElementById('topbar-title').textContent=titles[page]||page;
  const fn={dashboard:pgDashboard,sales:pgSales,clients:pgClients,products:pgProducts,
    stock:pgStock,orders:pgOrders,suppliers:pgSuppliers,stores:pgStores,
    reviews:pgReviews,reports:pgReports,sale_new:pgSaleNew,
    catalog:pgCatalog,my_purchases:pgMyPurchases}[page];
  if(fn) fn(); else setPage('<div class="empty-state"><div class="esi">🔧</div><p>Страница в разработке</p></div>');
}
function setPage(html){document.getElementById('page').innerHTML=html;}
function toggleSidebar(){document.getElementById('sidebar').classList.toggle('collapsed');}

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
  if(p>1) h+=`<button class="page-btn" onclick="${cb}(${p-1})">‹</button>`;
  for(let i=1;i<=total;i++) h+=`<button class="page-btn${i===p?' active':''}" onclick="${cb}(${i})">${i}</button>`;
  if(p<total) h+=`<button class="page-btn" onclick="${cb}(${p+1})">›</button>`;
  return h+'</div>';
}

// ── Modal ─────────────────────────────────────────────────────
function openModal(title,body,footer=''){
  document.getElementById('modal-title').textContent=title;
  document.getElementById('modal-body').innerHTML=body;
  document.getElementById('modal-footer').innerHTML=footer;
  document.getElementById('modal-overlay').classList.add('open');
}
function closeModal(){document.getElementById('modal-overlay').classList.remove('open');}
function closeModalIfBg(e){if(e.target===document.getElementById('modal-overlay'))closeModal();}
function showAlert(msg,type='ok',containerId='page-alert'){
  const el=document.getElementById(containerId);
  if(el){el.innerHTML=`<div class="alert alert-${type}">${esc(msg)}</div>`;
    setTimeout(()=>{el.innerHTML='';},4000);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: DASHBOARD
// ═══════════════════════════════════════════════════════════════
async function pgDashboard(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const [sales,products,stores,orders]=await Promise.all([
      get('/sales'),get('/products'),get('/stores'),get('/orders')]);
    const totalRev=sales.reduce((s,x)=>s+(x.total||0),0);
    const activeOrders=orders.filter(o=>['ожидается','В пути','В обработке'].includes(o.status)).length;
    setPage(`
    <div id="page-alert"></div>
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-value">${fmt(sales.length)}</div><div class="stat-label">Всего продаж</div><div class="stat-icon">🛒</div></div>
      <div class="stat-card"><div class="stat-value">${fmtMoney(totalRev)}</div><div class="stat-label">Общая выручка</div><div class="stat-icon">💰</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(products.length)}</div><div class="stat-label">Товаров в каталоге</div><div class="stat-icon">💎</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(stores.length)}</div><div class="stat-label">Магазинов</div><div class="stat-icon">🏪</div></div>
      <div class="stat-card"><div class="stat-value">${fmt(activeOrders)}</div><div class="stat-label">Активных заказов</div><div class="stat-icon">📋</div></div>
    </div>
    <div class="card">
      <div class="card-title">💡 Последние продажи</div>
      <div class="tbl-wrap"><table>
        <thead><tr><th>Дата</th><th>Клиент</th><th>Магазин</th><th>Сумма</th><th>Оплата</th></tr></thead>
        <tbody>${sales.slice(0,8).map(s=>`<tr>
          <td>${fmtDate(s.date)}</td><td>${esc(s.client)}</td>
          <td><span class="tag">${esc(s.store.split(',')[1]||s.store)}</span></td>
          <td><b>${fmtMoney(s.total)}</b></td>
          <td>${esc(s.payment)}</td></tr>`).join('')}
        </tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: SALES
// ═══════════════════════════════════════════════════════════════
let salesData=[],salesPage=1;
async function pgSales(fromVal='',toVal='',storeId=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const [data,stores]=await Promise.all([
      get('/sales',{from:fromVal,to:toVal,store_id:storeId}),
      get('/stores')]);
    salesData=data;salesPage=1;
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${storeId==s.id?'selected':''}>${esc(s.address)}</option>`).join('');
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="f-from" value="${fromVal}"></div>
        <div class="filter-group"><label>По</label><input type="date" id="f-to" value="${toVal}"></div>
        <div class="filter-group"><label>Магазин</label>
          <select id="f-store"><option value="">Все магазины</option>${storeOpts}</select></div>
        <button class="btn btn-primary btn-sm" onclick="pgSales(document.getElementById('f-from').value,document.getElementById('f-to').value,document.getElementById('f-store').value)">Применить</button>
        ${ROLE!=='CLIENT'?'<button class="btn btn-outline btn-sm" onclick="modalNewSale()">+ Новая продажа</button>':''}
      </div>
    </div>
    <div class="card">
      <div id="sales-table"></div>
    </div>`);
    renderSalesTable();
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderSalesTable(){
  const {items,total,page}=paginate(salesData,salesPage,PAGE_SIZE);
  document.getElementById('sales-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Дата</th><th>Клиент</th><th>Магазин</th><th>Кассир</th><th>Сумма</th><th>Оплата</th><th></th></tr></thead>
      <tbody>${items.map(s=>`<tr>
        <td>${s.id}</td><td>${fmtDate(s.date)}</td>
        <td>${esc(s.client||'—')}</td>
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
// PAGE: SALE NEW (Кассир — оформление продажи)
// ═══════════════════════════════════════════════════════════════
let saleCartItems=[];
async function pgSaleNew(){
  try{
    const [clients,stores,products]=await Promise.all([
      get('/clients'),get('/stores'),get('/products')]);
    const clientOpts=clients.map(c=>`<option value="${c.id}">${esc(c.fio||c.phone)} (${esc(c.phone)})</option>`).join('');
    const storeOpts=stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('');
    const prodOpts=products.map(p=>`<option value="${p.article}" data-price="${p.price}">${esc(p.name)} — ${fmtMoney(p.price)}</option>`).join('');
    saleCartItems=[];
    setPage(`
    <div id="page-alert"></div>
    <div style="display:grid;grid-template-columns:1fr 380px;gap:16px">
      <div>
        <div class="card">
          <div class="card-title">👤 Клиент и магазин</div>
          <div class="form-row">
            <div class="form-group"><label>Клиент</label><select id="sn-client">${clientOpts}</select></div>
            <div class="form-group"><label>Магазин</label><select id="sn-store">${storeOpts}</select></div>
          </div>
          <div class="form-group"><label>Способ оплаты</label>
            <select id="sn-pay">
              <option>Карта</option><option>Наличные</option><option>Безнал</option>
            </select>
          </div>
        </div>
        <div class="card">
          <div class="card-title">💎 Добавить товар</div>
          <div class="form-row">
            <div class="form-group"><label>Товар</label><select id="sn-prod">${prodOpts}</select></div>
            <div class="form-group"><label>Количество</label><input type="number" id="sn-qty" value="1" min="1"></div>
          </div>
          <button class="btn btn-outline btn-sm" onclick="saleAddItem()">+ Добавить в корзину</button>
        </div>
      </div>
      <div class="card" style="position:sticky;top:0;align-self:start">
        <div class="card-title">🛒 Корзина</div>
        <div id="sn-cart"><div class="empty-state" style="padding:20px"><p>Корзина пуста</p></div></div>
        <hr class="separator">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
          <b>Итого:</b><b id="sn-total" style="font-size:18px;color:var(--gold-dark)">0 ₽</b>
        </div>
        <button class="btn btn-primary" style="width:100%;justify-content:center" onclick="submitSale()">Оформить продажу</button>
      </div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function saleAddItem(){
  const sel=document.getElementById('sn-prod');
  const opt=sel.options[sel.selectedIndex];
  const article=+sel.value,price=+(opt.dataset.price||0),name=opt.text.split('—')[0].trim();
  const qty=+document.getElementById('sn-qty').value||1;
  const existing=saleCartItems.find(i=>i.article===article);
  if(existing) existing.qty+=qty;
  else saleCartItems.push({article,name,price,qty});
  renderSaleCart();
}
function saleRemoveItem(article){
  saleCartItems=saleCartItems.filter(i=>i.article!==article);
  renderSaleCart();
}
function renderSaleCart(){
  const total=saleCartItems.reduce((s,i)=>s+i.price*i.qty,0);
  document.getElementById('sn-total').textContent=fmtMoney(total);
  if(!saleCartItems.length){
    document.getElementById('sn-cart').innerHTML='<div class="empty-state" style="padding:20px"><p>Корзина пуста</p></div>';return;}
  document.getElementById('sn-cart').innerHTML=`<div class="items-list">${
    saleCartItems.map(i=>`<div class="item-row">
      <span>${esc(i.name)}</span>
      <span>${i.qty} × ${fmtMoney(i.price)}</span>
      <span class="item-row-del" onclick="saleRemoveItem(${i.article})">✕</span>
    </div>`).join('')}</div>`;
}
async function submitSale(){
  if(!saleCartItems.length)return alert('Добавьте товары в корзину');
  const clientId=+document.getElementById('sn-client').value;
  const storeId=+document.getElementById('sn-store').value;
  const payment=document.getElementById('sn-pay').value;
  // cashier_snils from REF
  try{
    await post('/sales',{client_id:clientId,cashier_snils:REF,store_id:storeId,
      payment_method:payment,items:saleCartItems.map(i=>({article:i.article,price:i.price,qty:i.qty}))});
    saleCartItems=[];
    showAlert('Продажа успешно оформлена!','ok','page-alert');
    pgSaleNew();
  }catch(e){showAlert(e.message,'err','page-alert');}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: PRODUCTS
// ═══════════════════════════════════════════════════════════════
let prodsData=[],prodsPage=1;
async function pgProducts(cat='',srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/products',{category:cat,search:srch});
    prodsData=data;prodsPage=1;
    const cats=[...new Set(data.map(p=>p.category))].sort();
    const catOpts=cats.map(c=>`<option value="${c}" ${cat===c?'selected':''}>${c}</option>`).join('');
    const canEdit=ROLE==='ADMIN'||ROLE==='MANAGER';
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Категория</label>
          <select id="p-cat"><option value="">Все категории</option>${catOpts}</select></div>
        <div class="filter-group"><label>Поиск</label>
          <input type="text" id="p-srch" value="${esc(srch)}" placeholder="Название товара..."></div>
        <button class="btn btn-primary btn-sm" onclick="pgProducts(document.getElementById('p-cat').value,document.getElementById('p-srch').value)">Найти</button>
        ${canEdit?'<button class="btn btn-outline btn-sm" onclick="modalProduct()">+ Добавить товар</button>':''}
      </div>
    </div>
    <div class="card"><div id="prods-table"></div></div>`);
    renderProdsTable(canEdit);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function renderProdsTable(canEdit){
  const {items,total,page}=paginate(prodsData,prodsPage,PAGE_SIZE);
  document.getElementById('prods-table').innerHTML=`
    <div class="tbl-wrap"><table>
      <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th>${canEdit?'<th></th>':''}</tr></thead>
      <tbody>${items.map(p=>`<tr>
        <td><code>${p.article}</code></td>
        <td>${esc(p.name)}</td>
        <td><span class="badge badge-gold">${esc(p.category)}</span></td>
        <td><b>${fmtMoney(p.price)}</b></td>
        ${canEdit?`<td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick='modalProduct(${JSON.stringify(p)})'>Изм.</button>
          <button class="btn btn-danger btn-xs" onclick="deleteProduct(${p.article})">Удал.</button>
        </td>`:''}
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setProdsPage')}`;
}
function setProdsPage(p){prodsPage=p;renderProdsTable(ROLE==='ADMIN'||ROLE==='MANAGER');}
function modalProduct(p=null){
  openModal(p?'Редактировать товар':'Новый товар',`
    <div class="form-group"><label>Артикул</label><input id="mp-art" type="number" value="${p?p.article:''}" ${p?'readonly':''}></div>
    <div class="form-group"><label>Название</label><input id="mp-name" value="${esc(p?p.name:'')}"></div>
    <div class="form-group"><label>Категория</label>
      <select id="mp-cat">
        ${['Кольца','Серьги','Браслеты','Подвески','Цепочки','Часы','Броши'].map(c=>`<option ${(p&&p.category===c)?'selected':''}>${c}</option>`).join('')}
      </select></div>
    <div class="form-group"><label>Цена (руб.)</label><input id="mp-price" type="number" value="${p?p.price:''}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveProduct(${p?p.article:0})">Сохранить</button>`);
}
async function saveProduct(art){
  const data={article:+document.getElementById('mp-art').value,
    name:document.getElementById('mp-name').value,
    category:document.getElementById('mp-cat').value,
    price:+document.getElementById('mp-price').value};
  try{
    if(art) await put('/products/'+art,data);
    else await post('/products',data);
    closeModal();pgProducts();
  }catch(e){alert(e.message);}
}
async function deleteProduct(art){
  if(!confirm('Удалить товар '+art+'?'))return;
  try{await del('/products/'+art);pgProducts();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: STOCK
// ═══════════════════════════════════════════════════════════════
async function pgStock(storeId='',thresh=''){
  try{
    const stores=await get('/stores');
    if(!storeId&&stores.length) storeId=stores[0].id;
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${storeId==s.id?'selected':''}>${esc(s.address)}</option>`).join('');
    const data=storeId?await get('/stores/'+storeId+'/stock',{threshold:thresh}):[];
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Магазин</label><select id="st-store">${storeOpts}</select></div>
        <div class="filter-group"><label>Остаток ≤</label><input type="number" id="st-thresh" value="${thresh}" placeholder="Порог (напр. 3)"></div>
        <button class="btn btn-primary btn-sm" onclick="pgStock(document.getElementById('st-store').value,document.getElementById('st-thresh').value)">Применить</button>
      </div>
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th><th>Остаток</th><th>Статус</th>${ROLE!=='CLIENT'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(r=>{
          const low=r.qty<=2,mid=r.qty<=5;
          const badge=r.qty===0?'badge-danger':low?'badge-warning':'badge-success';
          const label=r.qty===0?'Нет в наличии':low?'Критично':mid?'Мало':'В наличии';
          return`<tr>
            <td><code>${r.article}</code></td>
            <td>${esc(r.name)}</td>
            <td><span class="badge badge-gold">${esc(r.category)}</span></td>
            <td>${fmtMoney(r.price)}</td>
            <td><b>${r.qty}</b></td>
            <td><span class="badge ${badge}">${label}</span></td>
            ${ROLE!=='CLIENT'?`<td><button class="btn btn-ghost btn-xs" onclick="modalEditStock(${r.stock_id},${r.qty},${storeId})">Изм.</button></td>`:''}
          </tr>`;}).join('')}
        </tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalEditStock(stockId,qty,storeId){
  openModal('Изменить остаток',`
    <div class="form-group"><label>Новое количество</label>
    <input id="es-qty" type="number" value="${qty}" min="0"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveStock(${stockId},${storeId})">Сохранить</button>`);
}
async function saveStock(stockId,storeId){
  const qty=+document.getElementById('es-qty').value;
  try{await put('/stock/'+stockId,{qty,store_id:storeId});closeModal();pgStock(storeId);}
  catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: ORDERS
// ═══════════════════════════════════════════════════════════════
let ordersData=[],ordersPage=1;
async function pgOrders(storeId='',status='',suppId=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const [data,stores,suppliers]=await Promise.all([
      get('/orders',{store_id:storeId,status,supplier_id:suppId}),
      get('/stores'),get('/suppliers')]);
    ordersData=data;ordersPage=1;
    const storeOpts=stores.map(s=>`<option value="${s.id}" ${storeId==s.id?'selected':''}>${esc(s.address)}</option>`).join('');
    const suppOpts=suppliers.map(s=>`<option value="${s.id}" ${suppId==s.id?'selected':''}>${esc(s.name)}</option>`).join('');
    const statuses=['ожидается','В обработке','В пути','Доставлен','Отменен'];
    const statOpts=statuses.map(s=>`<option value="${s}" ${status===s?'selected':''}>${s}</option>`).join('');
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Магазин</label>
          <select id="or-store"><option value="">Все</option>${storeOpts}</select></div>
        <div class="filter-group"><label>Статус</label>
          <select id="or-stat"><option value="">Все статусы</option>${statOpts}</select></div>
        <div class="filter-group"><label>Поставщик</label>
          <select id="or-supp"><option value="">Все</option>${suppOpts}</select></div>
        <button class="btn btn-primary btn-sm" onclick="pgOrders(document.getElementById('or-store').value,document.getElementById('or-stat').value,document.getElementById('or-supp').value)">Применить</button>
        ${ROLE!=='CLIENT'?`<button class="btn btn-outline btn-sm" onclick="modalNewOrder(${JSON.stringify(stores).replace(/"/g,'&quot;')},${JSON.stringify(suppliers).replace(/"/g,'&quot;')},${JSON.stringify(data.map(()=>({}))).replace(/"/g,'&quot;')})">+ Новый заказ</button>`:''}
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
      <thead><tr><th>#</th><th>Дата</th><th>Магазин</th><th>Поставщик</th><th>Менеджер</th><th>Статус</th><th>Сумма</th><th></th></tr></thead>
      <tbody>${items.map(o=>`<tr>
        <td>${o.id}</td><td>${fmtDate(o.date)}</td>
        <td><small>${esc(o.store)}</small></td>
        <td><small>${esc(o.supplier)}</small></td>
        <td><small>${esc(o.manager)}</small></td>
        <td>${statusBadge(o.status)}</td>
        <td><b>${fmtMoney(o.total)}</b></td>
        <td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick="viewOrder(${o.id})">Детали</button>
          ${ROLE!=='CLIENT'?`<button class="btn btn-outline btn-xs" onclick="modalChangeOrderStatus(${o.id},'${o.status}')">Статус</button>`:''}
        </td>
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setOrdersPage')}`;
}
function setOrdersPage(p){ordersPage=p;renderOrdersTable();}
async function viewOrder(id){
  try{
    const o=await get('/orders/'+id);
    openModal('Заказ #'+id,`
      <div class="form-row" style="margin-bottom:12px">
        <div><label>Магазин</label><p>${esc(o.store)}</p></div>
        <div><label>Поставщик</label><p>${esc(o.supplier)}</p></div>
        <div><label>Менеджер</label><p>${esc(o.manager)}</p></div>
        <div><label>Дата</label><p>${fmtDate(o.date)}</p></div>
        <div><label>Статус</label><p>${statusBadge(o.status)}</p></div>
        <div><label>Итого</label><p><b>${fmtMoney(o.total)}</b></p></div>
      </div><hr class="separator">
      <div class="card-title" style="font-size:15px">Позиции</div>
      <div class="items-list">${(o.items||[]).map(i=>`
        <div class="item-row"><span>${esc(i.name)}</span>
        <span>${i.qty} шт × ${fmtMoney(i.price)}</span></div>`).join('')}
      </div>`,'<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}
function modalChangeOrderStatus(id,current){
  const statuses=['ожидается','В обработке','В пути','Доставлен','Отменен'];
  openModal('Изменить статус заказа #'+id,`
    <div class="form-group"><label>Новый статус</label>
      <select id="os-stat">${statuses.map(s=>`<option value="${s}" ${s===current?'selected':''}>${s}</option>`).join('')}</select>
    </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveOrderStatus(${id})">Сохранить</button>`);
}
async function saveOrderStatus(id){
  const status=document.getElementById('os-stat').value;
  try{await put('/orders/'+id+'/status',{status});closeModal();pgOrders();}catch(e){alert(e.message);}
}

// Modal: New Order with product list builder
let orderCartItems=[];
async function modalNewOrder_open(){
  const [stores,suppliers,products]=await Promise.all([get('/stores'),get('/suppliers'),get('/products')]);
  orderCartItems=[];
  const storeOpts=stores.map(s=>`<option value="${s.id}">${esc(s.address)}</option>`).join('');
  const suppOpts=suppliers.map(s=>`<option value="${s.id}">${esc(s.name)}</option>`).join('');
  const prodOpts=products.map(p=>`<option value="${p.article}" data-price="${p.price}">${esc(p.name)}</option>`).join('');
  openModal('Новый заказ поставщику',`
    <div class="form-row">
      <div class="form-group"><label>Магазин</label><select id="no-store">${storeOpts}</select></div>
      <div class="form-group"><label>Поставщик</label><select id="no-supp">${suppOpts}</select></div>
    </div>
    <hr class="separator">
    <div class="form-row">
      <div class="form-group"><label>Товар</label><select id="no-prod">${prodOpts}</select></div>
      <div class="form-group"><label>Кол-во</label><input type="number" id="no-qty" value="1" min="1"></div>
    </div>
    <button class="btn btn-outline btn-sm" onclick="orderAddItem()">+ Добавить</button>
    <div id="no-cart" style="margin-top:12px"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="submitNewOrder()">Создать заказ</button>`);
}
function orderAddItem(){
  const sel=document.getElementById('no-prod');
  const opt=sel.options[sel.selectedIndex];
  const article=+sel.value,name=opt.text,price=+(opt.dataset.price||0);
  const qty=+document.getElementById('no-qty').value||1;
  const ex=orderCartItems.find(i=>i.article===article);
  if(ex) ex.qty+=qty; else orderCartItems.push({article,name,price,qty});
  renderOrderCart();
}
function renderOrderCart(){
  if(!orderCartItems.length){document.getElementById('no-cart').innerHTML='';return;}
  document.getElementById('no-cart').innerHTML=`<div class="items-list">${
    orderCartItems.map(i=>`<div class="item-row">
      <span>${esc(i.name)}</span><span>${i.qty} шт</span>
      <span class="item-row-del" onclick="orderRemoveItem(${i.article})">✕</span>
    </div>`).join('')}</div>`;
}
function orderRemoveItem(a){orderCartItems=orderCartItems.filter(i=>i.article!==a);renderOrderCart();}
async function submitNewOrder(){
  if(!orderCartItems.length)return alert('Добавьте товары');
  const storeId=+document.getElementById('no-store').value;
  const suppId=+document.getElementById('no-supp').value;
  try{
    await post('/orders',{store_id:storeId,supplier_id:suppId,
      items:orderCartItems.map(i=>({article:i.article,qty:i.qty}))});
    closeModal();pgOrders();
  }catch(e){alert(e.message);}
}


// ═══════════════════════════════════════════════════════════════
// PAGE: CLIENTS
// ═══════════════════════════════════════════════════════════════
let clientsData=[],clientsPage=1;
async function pgClients(srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/clients',{search:srch});
    clientsData=data;clientsPage=1;
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Поиск</label>
          <input type="text" id="cl-srch" value="${esc(srch)}" placeholder="ФИО или телефон..."></div>
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
        <td>${esc(c.fio||'—')}</td>
        <td>${esc(c.phone)}</td>
        <td>${esc(c.email||'—')}</td>
        <td class="td-actions">
          <button class="btn btn-ghost btn-xs" onclick="viewClient(${c.id})">Профиль</button>
          <button class="btn btn-ghost btn-xs" onclick='modalEditClient(${JSON.stringify(c).replace(/'/g,"&#39;")})'>Изм.</button>
        </td>
      </tr>`).join('')}</tbody>
    </table></div>
    ${paginationHtml(page,total,'setClientsPage')}`;
}
function setClientsPage(p){clientsPage=p;renderClientsTable();}
async function viewClient(id){
  try{
    const [c,sales]=await Promise.all([get('/clients/'+id),get('/clients/'+id+'/sales')]);
    openModal('Клиент: '+esc(c.fio||c.phone),`
      <div class="form-row" style="margin-bottom:12px">
        <div><label>ФИО</label><p>${esc(c.fio||'—')}</p></div>
        <div><label>Телефон</label><p>${esc(c.phone)}</p></div>
        <div><label>Email</label><p>${esc(c.email||'—')}</p></div>
        <div><label>Покупок</label><p><b>${c.purchase_count}</b></p></div>
        <div><label>Потрачено</label><p><b>${fmtMoney(c.total_spent)}</b></p></div>
      </div><hr class="separator">
      <div class="card-title" style="font-size:15px">История покупок</div>
      <div class="tbl-wrap"><table>
        <thead><tr><th>Дата</th><th>Магазин</th><th>Сумма</th><th>Оплата</th></tr></thead>
        <tbody>${sales.slice(0,10).map(s=>`<tr>
          <td>${fmtDate(s.date)}</td><td><small>${esc(s.store)}</small></td>
          <td><b>${fmtMoney(s.total)}</b></td><td>${esc(s.payment)}</td></tr>`).join('')}
        </tbody></table></div>`,
      '<button class="btn btn-ghost" onclick="closeModal()">Закрыть</button>');
  }catch(e){alert(e.message);}
}
function modalEditClient(c){
  openModal('Редактировать клиента',`
    <div class="form-group"><label>ФИО</label><input id="ec-fio" value="${esc(c.fio||'')}"></div>
    <div class="form-row">
      <div class="form-group"><label>Телефон</label><input id="ec-phone" value="${esc(c.phone)}"></div>
      <div class="form-group"><label>Email</label><input id="ec-email" value="${esc(c.email||'')}"></div>
    </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveClient(${c.id})">Сохранить</button>`);
}
async function saveClient(id){
  const data={fio:document.getElementById('ec-fio').value,
    phone:document.getElementById('ec-phone').value,
    email:document.getElementById('ec-email').value};
  try{await put('/clients/'+id,data);closeModal();pgClients();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: SUPPLIERS
// ═══════════════════════════════════════════════════════════════
async function pgSuppliers(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/suppliers');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Поставщики</div>
      ${ROLE==='ADMIN'?'<button class="btn btn-outline" onclick="modalSupplier()">+ Добавить</button>':''}
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Название</th><th>Email</th><th>Телефон</th><th>Заказов</th>${ROLE==='ADMIN'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(s=>`<tr>
          <td><b>${esc(s.name)}</b></td>
          <td>${esc(s.email)}</td>
          <td>${esc(s.phone)}</td>
          <td><span class="badge badge-info">${s.order_count}</span></td>
          ${ROLE==='ADMIN'?`<td class="td-actions">
            <button class="btn btn-ghost btn-xs" onclick='modalSupplier(${JSON.stringify(s).replace(/'/g,"&#39;")})'>Изм.</button>
            <button class="btn btn-danger btn-xs" onclick="deleteSupplier(${s.id})">Удал.</button>
          </td>`:''}
        </tr>`).join('')}</tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalSupplier(s=null){
  openModal(s?'Редактировать поставщика':'Новый поставщик',`
    <div class="form-group"><label>Название</label><input id="sp-name" value="${esc(s?s.name:'')}"></div>
    <div class="form-group"><label>Email</label><input id="sp-email" type="email" value="${esc(s?s.email:'')}"></div>
    <div class="form-group"><label>Телефон</label><input id="sp-phone" value="${esc(s?s.phone:'')}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveSupplier(${s?s.id:0})">Сохранить</button>`);
}
async function saveSupplier(id){
  const data={name:document.getElementById('sp-name').value,
    email:document.getElementById('sp-email').value,
    phone:document.getElementById('sp-phone').value};
  try{
    if(id) await put('/suppliers/'+id,data);
    else await post('/suppliers',data);
    closeModal();pgSuppliers();
  }catch(e){alert(e.message);}
}
async function deleteSupplier(id){
  if(!confirm('Удалить поставщика?'))return;
  try{await del('/suppliers/'+id);pgSuppliers();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: STORES
// ═══════════════════════════════════════════════════════════════
async function pgStores(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/stores');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Магазины сети</div>
      ${ROLE==='ADMIN'?'<button class="btn btn-outline" onclick="modalStore()">+ Добавить</button>':''}
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>#</th><th>Адрес</th><th>Телефон</th><th>Менеджер</th>${ROLE==='ADMIN'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(s=>`<tr>
          <td>${s.id}</td>
          <td>${esc(s.address)}</td>
          <td>${esc(s.phone)}</td>
          <td>${esc(s.manager||'—')}</td>
          ${ROLE==='ADMIN'?`<td class="td-actions">
            <button class="btn btn-ghost btn-xs" onclick='modalStore(${JSON.stringify(s).replace(/'/g,"&#39;")})'>Изм.</button>
            <button class="btn btn-danger btn-xs" onclick="deleteStore(${s.id})">Удал.</button>
          </td>`:''}
        </tr>`).join('')}</tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalStore(s=null){
  openModal(s?'Редактировать магазин':'Новый магазин',`
    <div class="form-group"><label>Адрес</label><input id="ms-addr" value="${esc(s?s.address:'')}"></div>
    <div class="form-group"><label>Телефон</label><input id="ms-phone" value="${esc(s?s.phone:'')}"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="saveStore(${s?s.id:0})">Сохранить</button>`);
}
async function saveStore(id){
  const data={address:document.getElementById('ms-addr').value,phone:document.getElementById('ms-phone').value};
  try{
    if(id) await put('/stores/'+id,data);
    else await post('/stores',data);
    closeModal();pgStores();
  }catch(e){alert(e.message);}
}
async function deleteStore(id){
  if(!confirm('Удалить магазин #'+id+'?'))return;
  try{await del('/stores/'+id);pgStores();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: REVIEWS
// ═══════════════════════════════════════════════════════════════
async function pgReviews(){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/reviews');
    setPage(`
    <div id="page-alert"></div>
    <div class="section-header">
      <div class="section-title">Отзывы клиентов</div>
      ${ROLE==='CLIENT'?'<button class="btn btn-outline" onclick="modalNewReview()">+ Оставить отзыв</button>':''}
    </div>
    <div class="card">
      <div class="tbl-wrap"><table>
        <thead><tr><th>Клиент</th><th>Рейтинг</th><th>Комментарий</th><th>Дата</th>${ROLE==='ADMIN'?'<th></th>':''}</tr></thead>
        <tbody>${data.map(r=>`<tr>
          <td><b>${esc(r.client||'—')}</b></td>
          <td><span class="stars">${stars(r.rating)}</span></td>
          <td>${esc(r.comment||'—')}</td>
          <td>${fmtDate(r.date)}</td>
          ${ROLE==='ADMIN'?`<td><button class="btn btn-danger btn-xs" onclick="deleteReview(${r.id})">Удал.</button></td>`:''}
        </tr>`).join('')}</tbody>
      </table></div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}
function modalNewReview(){
  openModal('Оставить отзыв',`
    <div class="form-group"><label>Рейтинг</label>
      <select id="rv-rating">
        <option value="5">★★★★★ — Отлично</option>
        <option value="4">★★★★☆ — Хорошо</option>
        <option value="3">★★★☆☆ — Нормально</option>
        <option value="2">★★☆☆☆ — Плохо</option>
        <option value="1">★☆☆☆☆ — Ужасно</option>
      </select></div>
    <div class="form-group"><label>Комментарий</label>
      <textarea id="rv-comment" placeholder="Расскажите о вашем опыте..."></textarea></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="submitReview()">Отправить</button>`);
}
async function submitReview(){
  const rating=+document.getElementById('rv-rating').value;
  const comment=document.getElementById('rv-comment').value;
  try{
    await post('/reviews',{client_id:+REF,rating,comment});
    closeModal();pgReviews();
  }catch(e){alert(e.message);}
}
async function deleteReview(id){
  if(!confirm('Удалить отзыв?'))return;
  try{await del('/reviews/'+id);pgReviews();}catch(e){alert(e.message);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: REPORTS — 4 отчёта из ТЗ + топ клиентов
// ═══════════════════════════════════════════════════════════════
async function pgReports(){
  setPage(`
  <div id="page-alert"></div>
  <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:14px;margin-bottom:16px">
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('sales_by_cat')">
      <div class="card-title">📊 Продажи по категориям</div>
      <p style="font-size:12px;color:var(--smoke)">Выручка, количество и доля по каждой категории товаров за период</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('stock_status')">
      <div class="card-title">📦 Остатки в магазине</div>
      <p style="font-size:12px;color:var(--smoke)">Товары с критическим остатком, требующие пополнения</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('orders_rep')">
      <div class="card-title">📋 Заказы поставщикам</div>
      <p style="font-size:12px;color:var(--smoke)">Все заказы по поставщикам, периодам и статусам</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('revenue')">
      <div class="card-title">💰 Выручка по магазинам</div>
      <p style="font-size:12px;color:var(--smoke)">Сравнительный анализ выручки, транзакций и среднего чека</p>
    </div>
    <div class="card" style="cursor:pointer;border-color:var(--gold-light)" onclick="loadReport('top_clients')">
      <div class="card-title">👑 Топ клиентов</div>
      <p style="font-size:12px;color:var(--smoke)">Лучшие клиенты по объёму покупок за период</p>
    </div>
  </div>
  <div id="report-result"></div>`);
}

async function loadReport(type){
  const el=document.getElementById('report-result');
  if(!el)return;
  el.innerHTML='<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>';
  try{
    if(type==='sales_by_cat') await reportSalesByCat();
    else if(type==='stock_status') await reportStock();
    else if(type==='orders_rep') await reportOrders();
    else if(type==='revenue') await reportRevenue();
    else if(type==='top_clients') await reportTopClients();
  }catch(e){el.innerHTML=`<div class="alert alert-err">${esc(e.message)}</div>`;}
}

async function reportSalesByCat(){
  const today=new Date().toISOString().slice(0,10);
  const from='2024-01-01';
  const data=await get('/reports/sales-by-category',{from,to:today});
  const max=Math.max(...data.map(r=>r.revenue),1);
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">📊 Продажи по категориям
      <span style="font-size:12px;color:var(--smoke);font-family:'DM Sans',sans-serif">${fmtDate(from)} — ${fmtDate(today)}</span>
    </div>
    <div class="chart-bar-wrap">${data.map(r=>`
      <div class="chart-bar-row">
        <div class="chart-bar-label">${esc(r.category)}</div>
        <div class="chart-bar-track">
          <div class="chart-bar-fill" style="width:${(r.revenue/max*100).toFixed(1)}%">
            ${r.pct}%
          </div>
        </div>
        <div class="chart-bar-val">${fmtMoney(r.revenue)}</div>
      </div>`).join('')}
    </div>
    <hr class="separator">
    <div class="tbl-wrap"><table>
      <thead><tr><th>Категория</th><th>Кол-во ед.</th><th>Выручка</th><th>Доля %</th></tr></thead>
      <tbody>${data.map(r=>`<tr>
        <td><span class="badge badge-gold">${esc(r.category)}</span></td>
        <td>${fmt(r.qty)}</td>
        <td><b>${fmtMoney(r.revenue)}</b></td>
        <td>${r.pct}%</td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

async function reportStock(){
  const stores=await get('/stores');
  if(!stores.length)return;
  const storeId=stores[0].id;
  const data=await get('/reports/stock-status',{store_id:storeId,threshold:5});
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">📦 Остатки в магазине: <span style="font-size:14px;font-family:'DM Sans'">${esc(stores[0].address)}</span></div>
    <div style="margin-bottom:12px">
      <span class="badge badge-danger" style="margin-right:8px">Нет в наличии: ${data.filter(r=>r.qty===0).length}</span>
      <span class="badge badge-warning" style="margin-right:8px">Критично (≤2): ${data.filter(r=>r.qty>0&&r.qty<=2).length}</span>
      <span class="badge badge-info">Мало (≤5): ${data.filter(r=>r.qty>2&&r.qty<=5).length}</span>
    </div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Артикул</th><th>Название</th><th>Категория</th><th>Цена</th><th>Остаток</th><th>Статус</th></tr></thead>
      <tbody>${data.map(r=>{
        const badge=r.qty===0?'badge-danger':r.qty<=2?'badge-warning':'badge-info';
        const label=r.qty===0?'Нет':r.qty<=2?'Критично':'Мало';
        return`<tr>
          <td><code>${r.article}</code></td><td>${esc(r.name)}</td>
          <td><span class="badge badge-gold">${esc(r.category)}</span></td>
          <td>${fmtMoney(r.price)}</td><td><b>${r.qty}</b></td>
          <td><span class="badge ${badge}">${label}</span></td></tr>`}).join('')}
      </tbody></table></div>
  </div>`;
}

async function reportOrders(){
  const data=await get('/reports/orders',{});
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">📋 Заказы поставщикам</div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Дата</th><th>Поставщик</th><th>Магазин</th><th>Менеджер</th><th>Статус</th><th>Сумма</th></tr></thead>
      <tbody>${data.map(r=>`<tr>
        <td>${r.id}</td><td>${fmtDate(r.date)}</td>
        <td>${esc(r.supplier)}</td><td><small>${esc(r.store)}</small></td>
        <td><small>${esc(r.manager)}</small></td>
        <td>${statusBadge(r.status)}</td>
        <td><b>${fmtMoney(r.total)}</b></td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

async function reportRevenue(){
  const from='2024-01-01',to=new Date().toISOString().slice(0,10);
  const data=await get('/reports/revenue-by-store',{from,to});
  const max=Math.max(...data.map(r=>r.revenue),1);
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">💰 Выручка по магазинам
      <span style="font-size:12px;color:var(--smoke);font-family:'DM Sans'">${fmtDate(from)} — ${fmtDate(to)}</span>
    </div>
    <div class="chart-bar-wrap" style="margin-bottom:16px">${data.map(r=>`
      <div class="chart-bar-row">
        <div class="chart-bar-label">${esc(r.store.split(',')[1]?.trim()||r.store)}</div>
        <div class="chart-bar-track">
          <div class="chart-bar-fill" style="width:${(r.revenue/max*100).toFixed(1)}%">
            ${fmtMoney(r.revenue)}
          </div>
        </div>
        <div class="chart-bar-val">${r.tx_count} прод.</div>
      </div>`).join('')}
    </div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Магазин</th><th>Выручка</th><th>Транзакций</th><th>Средний чек</th></tr></thead>
      <tbody>${data.map(r=>`<tr>
        <td>${esc(r.store)}</td>
        <td><b>${fmtMoney(r.revenue)}</b></td>
        <td>${fmt(r.tx_count)}</td>
        <td>${fmtMoney(r.avg_check)}</td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

async function reportTopClients(){
  const from='2024-01-01',to=new Date().toISOString().slice(0,10);
  const data=await get('/reports/top-customers',{from,to,limit:10});
  document.getElementById('report-result').innerHTML=`
  <div class="card">
    <div class="card-title">👑 Топ-10 клиентов по выручке</div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>№</th><th>ФИО</th><th>Телефон</th><th>Покупок</th><th>Сумма</th><th>Средний чек</th></tr></thead>
      <tbody>${data.map((r,i)=>`<tr>
        <td><span class="badge ${i<3?'badge-gold':''}">${i+1}</span></td>
        <td><b>${esc(r.fio||'—')}</b></td>
        <td>${esc(r.phone)}</td>
        <td>${r.count}</td>
        <td><b>${fmtMoney(r.total)}</b></td>
        <td>${fmtMoney(r.avg)}</td>
      </tr>`).join('')}</tbody>
    </table></div>
  </div>`;
}

// ═══════════════════════════════════════════════════════════════
// PAGE: CATALOG (клиент)
// ═══════════════════════════════════════════════════════════════
async function pgCatalog(cat='',srch=''){
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/products',{category:cat,search:srch});
    const cats=[...new Set(data.map(p=>p.category))].sort();
    const catOpts=cats.map(c=>`<option value="${c}" ${cat===c?'selected':''}>${c}</option>`).join('');
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>Категория</label>
          <select id="cat-cat"><option value="">Все категории</option>${catOpts}</select></div>
        <div class="filter-group"><label>Поиск</label>
          <input type="text" id="cat-srch" value="${esc(srch)}" placeholder="Название..."></div>
        <button class="btn btn-primary btn-sm" onclick="pgCatalog(document.getElementById('cat-cat').value,document.getElementById('cat-srch').value)">Найти</button>
      </div>
    </div>
    <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:14px;margin-top:14px">
      ${data.map(p=>`
      <div class="card" style="padding:16px;margin-bottom:0">
        <div style="font-size:28px;text-align:center;margin-bottom:10px">💍</div>
        <div style="font-weight:600;margin-bottom:4px;font-size:13px">${esc(p.name)}</div>
        <div style="margin-bottom:8px"><span class="badge badge-gold">${esc(p.category)}</span></div>
        <div style="font-family:'Cormorant Garamond',serif;font-size:20px;color:var(--gold-dark);font-weight:400">${fmtMoney(p.price)}</div>
        <div style="font-size:11px;color:var(--smoke);margin-top:2px">Арт. ${p.article}</div>
      </div>`).join('')}
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// ═══════════════════════════════════════════════════════════════
// PAGE: MY PURCHASES (клиент)
// ═══════════════════════════════════════════════════════════════
async function pgMyPurchases(from='',to=''){
  if(!REF)return setPage('<div class="alert alert-err">Не определён профиль клиента</div>');
  setPage('<div class="empty-state"><div class="esi">⏳</div><p>Загрузка...</p></div>');
  try{
    const data=await get('/clients/'+REF+'/sales',{from,to});
    setPage(`
    <div id="page-alert"></div>
    <div class="card" style="margin-bottom:0;padding:14px 20px">
      <div class="filters">
        <div class="filter-group"><label>С</label><input type="date" id="mp-from" value="${from}"></div>
        <div class="filter-group"><label>По</label><input type="date" id="mp-to" value="${to}"></div>
        <button class="btn btn-primary btn-sm" onclick="pgMyPurchases(document.getElementById('mp-from').value,document.getElementById('mp-to').value)">Применить</button>
      </div>
    </div>
    <div class="card">
      ${!data.length?'<div class="empty-state"><div class="esi">🛍️</div><p>Покупок пока нет</p></div>':''}
      <div class="tbl-wrap">${data.length?`<table>
        <thead><tr><th>Дата</th><th>Магазин</th><th>Товары</th><th>Сумма</th><th>Оплата</th></tr></thead>
        <tbody>${data.map(s=>`<tr>
          <td>${fmtDate(s.date)}</td>
          <td><small>${esc(s.store)}</small></td>
          <td><small>${esc((s.products||'').replace(/[{}"]/g,''))}</small></td>
          <td><b>${fmtMoney(s.total)}</b></td>
          <td>${esc(s.payment)}</td>
        </tr>`).join('')}</tbody>
      </table>`:''}
      </div>
    </div>`);
  }catch(e){setPage(`<div class="alert alert-err">${esc(e.message)}</div>`);}
}

// ═══════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded',()=>{
  tryAutoLogin();
  document.getElementById('au-pass')?.addEventListener('keydown',e=>{if(e.key==='Enter')doLogin();});
  document.getElementById('au-user')?.addEventListener('keydown',e=>{if(e.key==='Enter')doLogin();});
});
