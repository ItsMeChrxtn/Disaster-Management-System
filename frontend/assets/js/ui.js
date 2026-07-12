(() => {
  const flash=sessionStorage.getItem('dm_flash');if(flash){sessionStorage.removeItem('dm_flash');try{const value=JSON.parse(flash);setTimeout(()=>toast(value.message,value.icon||'success'),150);}catch{}}
  const html=document.documentElement;
  const savedTheme=localStorage.getItem('dm_theme');
  if(savedTheme==='dark'||(!savedTheme&&matchMedia('(prefers-color-scheme: dark)').matches)) html.classList.add('dark');

  const header=document.querySelector('header');
  const avatar=document.getElementById('avatar');
  if(header&&avatar){
    const controls=document.createElement('div');
    controls.className='topbar-actions';
    controls.innerHTML=`<div class="global-search"><span aria-hidden="true">Search</span><input id="globalSearch" type="search" placeholder="Search this page" aria-label="Search visible records"></div><button id="themeToggle" class="icon-button" aria-label="Toggle dark mode">Mode</button><div class="notification-center"><button id="notificationBell" class="icon-button" aria-label="Notifications">Alerts<span id="notificationCount" class="notification-count hidden">0</span></button><div id="notificationDropdown" class="notification-dropdown hidden"><div class="notification-heading"><strong>Notifications</strong><button id="markAllRead" type="button">Mark all read</button></div><div id="notificationPreview" class="notification-list"><p class="empty-note">No notifications.</p></div><button id="openAlertCenter" class="notification-footer">Open alert center</button></div></div>`;
    header.insertBefore(controls,avatar);
    const userMenu=document.createElement('div');userMenu.className='user-menu';avatar.parentNode.insertBefore(userMenu,avatar);userMenu.appendChild(avatar);avatar.setAttribute('role','button');avatar.setAttribute('tabindex','0');avatar.setAttribute('aria-label','Open user menu');
    const dropdown=document.createElement('div');dropdown.className='user-dropdown hidden';dropdown.innerHTML='<button data-user-action="profile">Profile & security</button><button data-user-action="theme">Toggle appearance</button><button data-user-action="logout" class="text-red-600">Sign out</button>';userMenu.appendChild(dropdown);controls.appendChild(userMenu);
    avatar.addEventListener('click',()=>dropdown.classList.toggle('hidden'));dropdown.addEventListener('click',event=>{const action=event.target.dataset.userAction;if(action==='profile')document.querySelector('[data-view="profile"]')?.click();if(action==='theme')document.getElementById('themeToggle')?.click();if(action==='logout')document.getElementById('logoutBtn')?.click();dropdown.classList.add('hidden');});
  }

  const icons={overview:'<path d="M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v6h8V3h-8Z"/>',weather:'<path d="M6.5 19a4.5 4.5 0 0 1-.5-8.97A6 6 0 0 1 17.8 8.5 5.25 5.25 0 1 1 18.75 19H6.5Z"/>',municipalities:'<path d="M4 21V8l8-5 8 5v13h-6v-7h-4v7H4Z"/>',hazards:'<path d="m12 3 10 18H2L12 3Zm0 6v5m0 3v1"/>',safezones:'<path d="M12 22s8-5.4 8-13a8 8 0 1 0-16 0c0 7.6 8 13 8 13Zm-3-12 2 2 4-4"/>',centers:'<path d="M4 4h16v16H4V4Zm8 4v8m-4-4h8"/>',alerts:'<path d="M18 8a6 6 0 1 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Zm-8 12h4"/>',history:'<path d="M3 12a9 9 0 1 0 3-6.7L3 8m0-5v5h5m4-1v5l4 2"/>',reports:'<path d="M6 3h9l4 4v14H6V3Zm8 0v5h5M9 13h7m-7 4h7"/>',users:'<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m7-10a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm8 0 2 2 4-4"/>',profile:'<path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm7 9a7 7 0 0 0-14 0"/>'};
  document.querySelectorAll('.nav-item').forEach(item=>{const icon=document.createElementNS('http://www.w3.org/2000/svg','svg');icon.setAttribute('viewBox','0 0 24 24');icon.setAttribute('fill','none');icon.setAttribute('stroke','currentColor');icon.setAttribute('stroke-width','1.8');icon.classList.add('nav-icon');icon.innerHTML=icons[item.dataset.view]||icons.overview;item.prepend(icon);});
  const moduleMeta={
    overview:['Command overview','Live operating picture','KPIs','Charts','Active alerts'],
    weather:['Weather command','Derived advisories','Conditions','Wind','Warnings'],
    municipalities:['Municipal registry','Jurisdiction directory','Records','Status','Coverage'],
    hazards:['Hazard command','Map and classify risk zones','Draw','Validate','Publish'],
    safezones:['Safe zone command','Verified public safety locations','Capacity','Location','Access'],
    centers:['Evacuation center command','Facility status and capacity','Status','Contacts','Capacity'],
    alerts:['Alert command','Create and monitor advisories','Draft','Send','Notify'],
    history:['Historical archive','Recorded incidents and impact','Casualties','Damages','Dates'],
    reports:['Reporting desk','Generate and download reports','Scope','Export','Archive'],
    users:['User administration','Manage roles and account status','Roles','Access','Status'],
    profile:['Security profile','Account and password management','Identity','Password','Audit']
  };
  document.querySelectorAll('main>.view').forEach(view=>{
    const key=view.id.replace('view-',''),meta=moduleMeta[key]||['Operations','Manage records','Search','Review','Export'];
    const crumb=document.createElement('div');crumb.className='app-breadcrumb';crumb.innerHTML='<span>Operations</span><span>/</span><strong></strong>';view.prepend(crumb);
    if(!view.querySelector('.module-command-strip')){
      const strip=document.createElement('div');
      strip.className='module-command-strip';
      strip.innerHTML=`<div><span>${meta[0]}</span><strong>${meta[1]}</strong></div><ul><li>${meta[2]}</li><li>${meta[3]}</li><li>${meta[4]}</li></ul>`;
      crumb.after(strip);
    }
  });
  const activeNav=document.querySelector('.nav-item.nav-active');if(activeNav)document.querySelector(`#view-${activeNav.dataset.view} .app-breadcrumb strong`)?.replaceChildren(activeNav.textContent.trim());
  const stats=document.getElementById('stats');if(stats&&!stats.children.length)stats.innerHTML=Array.from({length:6},()=>'<article class="skeleton h-32 rounded-2xl"></article>').join('');

  document.getElementById('themeToggle')?.addEventListener('click',()=>{html.classList.toggle('dark');localStorage.setItem('dm_theme',html.classList.contains('dark')?'dark':'light');});
  document.getElementById('globalSearch')?.addEventListener('input',e=>{const value=e.target.value.toLowerCase().trim();document.querySelectorAll('.view:not(.hidden) tbody tr').forEach(row=>row.hidden=!!value&&!row.textContent.toLowerCase().includes(value));});
  document.getElementById('notificationBell')?.addEventListener('click',e=>{e.stopPropagation();document.getElementById('notificationDropdown')?.classList.toggle('hidden');refreshNotifications();});
  document.addEventListener('click',e=>{if(!e.target.closest('.notification-center'))document.getElementById('notificationDropdown')?.classList.add('hidden');});
  document.getElementById('openAlertCenter')?.addEventListener('click',()=>document.querySelector('[data-view="alerts"]')?.click());
  document.querySelectorAll('.nav-item').forEach(item=>item.addEventListener('click',()=>{const label=item.textContent.trim().replace(/\d+$/,'').trim();document.querySelector(`#view-${item.dataset.view} .app-breadcrumb strong`)?.replaceChildren(label);if(innerWidth<1024)document.getElementById('sidebar')?.classList.add('hidden');}));

  async function refreshNotifications(){
    if(!window.Api?.token())return;
    try{
      const rows=await Api.get('/notifications/history');
      const unread=rows.filter(x=>!x.is_read),count=document.getElementById('notificationCount');
      count.textContent=unread.length;count.classList.toggle('hidden',!unread.length);
      document.getElementById('notificationPreview').innerHTML=rows.slice(0,6).map(x=>`<button class="notification-item ${x.is_read?'':'unread'}" data-notification-id="${x.id}"><strong>${escapeHtml(x.title)}</strong><span>${escapeHtml(x.message)}</span><small>${new Date(x.sent_at||x.created_at).toLocaleString()}</small></button>`).join('')||'<p class="empty-note">No notifications.</p>';
    }catch{}
  }
  document.getElementById('notificationPreview')?.addEventListener('click',async e=>{const item=e.target.closest('[data-notification-id]');if(!item)return;try{await Api.post(`/notifications/${item.dataset.notificationId}/read`,{});refreshNotifications();}catch(err){showError(err.message);}});
  document.getElementById('markAllRead')?.addEventListener('click',async()=>{try{const rows=await Api.get('/notifications/history');await Promise.all(rows.filter(x=>!x.is_read).map(x=>Api.post(`/notifications/${x.id}/read`,{})));toast('Notifications marked as read');refreshNotifications();}catch(err){showError(err.message);}});
  const escapeHtml=value=>{const el=document.createElement('span');el.textContent=value??'';return el.innerHTML;};

  class SmartTable {
    constructor(table){
      this.table=table;
      this.page=1;
      this.size=10;
      this.sortIndex=-1;
      this.ascending=true;
      this.statusFilter='all';
      this.wrapper=table.closest('.overflow-x-auto')||table.parentElement;
      this.viewKey=table.closest('.view')?.id?.replace(/^view-/,'')||'records';
      this.wrapper.classList.remove('admin-data-table-card');
      this.wrapper.classList.add('admin-table-card',`${this.viewKey}-table-card`);
      this.build();
      this.observe();
    }
    build(){
      const existingBar=this.wrapper.dataset.customTableToolbar==='true'?this.wrapper.querySelector('.admin-table-toolbar'):null;
      const title=this.table.tBodies[0]?.id?.replace(/Table$/,'').replace(/([A-Z])/g,' $1').trim()||'records';
      const bar=existingBar||document.createElement('div');
      bar.classList.add(`${this.viewKey}-table-toolbar`);
      if(!existingBar){
        bar.className=`table-toolbar admin-table-toolbar ${this.viewKey}-table-toolbar`;
        bar.innerHTML=`<div class="table-toolbar-title"><span>Records</span><strong>${title.charAt(0).toUpperCase()+title.slice(1)}</strong></div><label class="table-search"><span>Search</span><input type="search" placeholder="Search records" aria-label="Search table"></label><div class="table-export-group" aria-label="Table export actions"><button data-export="csv" title="Export CSV">CSV</button><button data-export="excel" title="Export Excel">Excel</button><button data-export="pdf" title="Print to PDF">PDF</button><button data-export="print" title="Print table">Print</button></div>`;
        this.wrapper.insertBefore(bar,this.table);
      }
      if(this.viewKey==='municipalities'&&!bar.querySelector('.municipality-toolbar-controls')){
        const search=bar.querySelector('.table-search');
        const controls=document.createElement('div');
        controls.className='municipality-toolbar-controls';
        controls.innerHTML='<div class="municipality-status-filter" role="group" aria-label="Filter municipalities by status"><button type="button" data-status-filter="all" class="is-active">All</button><button type="button" data-status-filter="active">Active</button><button type="button" data-status-filter="inactive">Inactive</button></div>';
        if(search){
          controls.appendChild(search);
          bar.appendChild(controls);
        }
        controls.addEventListener('click',event=>{
          const button=event.target.closest('[data-status-filter]');
          if(!button)return;
          this.statusFilter=button.dataset.statusFilter;
          controls.querySelectorAll('[data-status-filter]').forEach(item=>item.classList.toggle('is-active',item===button));
          this.page=1;
          this.render();
        });
      }
      const footer=document.createElement('div');
      footer.className=`table-footer admin-table-footer ${this.viewKey}-table-footer`;
      footer.innerHTML='<span></span><div><button data-page="prev">Previous</button><button data-page="next">Next</button></div>';
      this.wrapper.appendChild(footer);
      this.bar=bar;
      this.footer=footer;
      bar.querySelector('input')?.addEventListener('input',()=>{this.page=1;this.render();});
      bar.onclick=event=>{const type=event.target.dataset.export;if(type)this.export(type);};
      footer.onclick=event=>{if(event.target.dataset.page==='prev')this.page=Math.max(1,this.page-1);if(event.target.dataset.page==='next')this.page++;this.render();};
      this.table.querySelectorAll('thead th').forEach((th,index)=>{
        if(/action/i.test(th.textContent))return;
        th.classList.add('sortable');
        th.title='Sort column';
        th.addEventListener('click',()=>{this.ascending=this.sortIndex===index?!this.ascending:true;this.sortIndex=index;this.render();});
      });
    }
    observe(){
      const body=this.table.tBodies[0];
      if(!body)return;
      new MutationObserver(()=>{if(!this.rendering){this.page=1;this.render();}}).observe(body,{childList:true});
      this.render();
    }
    rows(){return [...this.table.tBodies[0].rows].filter(row=>!row.querySelector('td[colspan]'));}
    filtered(){
      const q=this.bar.querySelector('input')?.value.toLowerCase().trim()||'';
      let rows=this.rows().filter(row=>!q||row.textContent.toLowerCase().includes(q));
      if(this.viewKey==='municipalities'&&this.statusFilter!=='all'){
        rows=rows.filter(row=>(row.querySelector('.municipality-status-pill')?.textContent||row.cells[2]?.innerText||'').trim().toLowerCase()===this.statusFilter);
      }
      if(this.sortIndex>=0)rows.sort((a,b)=>a.cells[this.sortIndex].innerText.localeCompare(b.cells[this.sortIndex].innerText,undefined,{numeric:true})*(this.ascending?1:-1));
      return rows;
    }
    render(){
      this.rendering=true;
      const rows=this.filtered(),pages=Math.max(1,Math.ceil(rows.length/this.size));
      this.page=Math.min(this.page,pages);
      this.rows().forEach(row=>row.hidden=true);
      rows.slice((this.page-1)*this.size,this.page*this.size).forEach(row=>row.hidden=false);
      this.footer.firstElementChild.textContent=rows.length?`Showing ${(this.page-1)*this.size+1}-${Math.min(this.page*this.size,rows.length)} of ${rows.length} records`:'No matching records';
      this.footer.querySelector('[data-page="prev"]').disabled=this.page===1;
      this.footer.querySelector('[data-page="next"]').disabled=this.page===pages;
      this.rendering=false;
    }
    data(){
      const headers=[...this.table.tHead.rows[0].cells].map(cell=>cell.innerText.trim()).filter(value=>!/action/i.test(value));
      return [headers,...this.filtered().map(row=>[...row.cells].slice(0,headers.length).map(cell=>cell.innerText.trim()))];
    }
    export(type){
      const data=this.data(),name=`disaster-map-${new Date().toISOString().slice(0,10)}`;
      if(type==='print'){
        const win=open('','_blank');
        win.document.write(`<title>${name}</title><style>body{font:12px Arial}table{border-collapse:collapse;width:100%}th,td{border:1px solid #bbb;padding:8px}</style>${this.table.outerHTML}`);
        win.document.close();
        win.print();
        return toast('Print view opened');
      }
      if(type==='pdf'){window.print();return toast('Choose Save as PDF in the print dialog');}
      const separator=type==='excel'?'\t':',';
      const text=data.map(row=>row.map(value=>type==='excel'?value:`"${value.replaceAll('"','""')}"`).join(separator)).join('\n');
      const blob=new Blob([type==='excel'?'\ufeff'+text:text],{type:type==='excel'?'application/vnd.ms-excel':'text/csv'});
      const anchor=document.createElement('a');
      anchor.href=URL.createObjectURL(blob);
      anchor.download=`${name}.${type==='excel'?'xls':'csv'}`;
      anchor.click();
      URL.revokeObjectURL(anchor.href);
      toast(`${type==='excel'?'Excel':'CSV'} export created`);
    }
  }
  document.querySelectorAll('main table').forEach(table=>new SmartTable(table));
  async function initOverviewMap(){const grid=document.querySelector('#view-overview .mt-6.grid');if(!grid||!window.L)return;const card=document.createElement('article');card.className='overflow-hidden rounded-2xl border bg-white xl:col-span-2';card.innerHTML='<div class="flex items-center justify-between border-b p-5"><div><h2 class="font-semibold">Operational map preview</h2><p class="text-xs text-slate-500">Current hazards and response facilities</p></div><button class="text-xs font-bold text-blue-600">Open full map</button></div><div id="overviewMap" class="h-80"></div>';grid.appendChild(card);card.querySelector('button').onclick=()=>location.href='index.html';const preview=L.map('overviewMap',{zoomControl:false,attributionControl:false,scrollWheelZoom:false}).setView(Config.MAP_CENTER,Config.MAP_ZOOM);L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:18}).addTo(preview);try{const data=await Api.get('/gis/layers'),group=L.featureGroup().addTo(preview);[...data.flood_layer,...data.storm_surge_layer,...data.earthquake_layer].forEach(item=>L.geoJSON(item.geojson_data,{style:{color:item.risk_level==='critical'?'#dc2626':item.risk_level==='high'?'#f97316':'#2563eb',weight:2,fillOpacity:.18}}).addTo(group));data.safe_zone_layer.forEach(item=>L.circleMarker([item.latitude,item.longitude],{radius:5,color:'#059669',fillOpacity:1}).bindTooltip(item.safezone_name).addTo(group));data.evacuation_center_layer.forEach(item=>L.circleMarker([item.latitude,item.longitude],{radius:5,color:'#7c3aed',fillOpacity:1}).bindTooltip(item.center_name).addTo(group));const bounds=group.getBounds();if(bounds.isValid())preview.fitBounds(bounds,{padding:[20,20],maxZoom:12});}catch{card.querySelector('#overviewMap').innerHTML='<div class="empty-note">Map preview is temporarily unavailable.</div>';}}
  initOverviewMap();
  refreshNotifications();setInterval(refreshNotifications,60000);
})();
