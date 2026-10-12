// The site is Dark by default. A header toggle switches to the light (Sunlight) appearance and
// remembers it in localStorage. This script runs inline in <head>, before first paint, so a saved
// choice never flashes. It is the site's only client script of its own; nginx's CSP allows inline
// scripts ('unsafe-inline'). Every localStorage access is wrapped in try/catch because storage can
// be blocked (private windows, strict privacy settings); the site then simply stays Dark.
//
// - html[data-theme="light"] selects the light tokens in globals.css; no attribute means Dark.
// - html[data-js] shows the toggle, which is hidden when scripts do not run.
// - The toggle (#theme-toggle) is a button with aria-pressed="true" while the light theme is on.
// - Links marked data-current-match (the brand and the footer's page links) get
//   aria-current="page" when they point at the page being shown. The layout is shared and static,
//   so it cannot know the current path at build time.

export const THEME_STORAGE_KEY = "showrecorder-theme";

export const THEME_SCRIPT = String.raw`(function(){
var d=document.documentElement,k=${JSON.stringify(THEME_STORAGE_KEY)};
try{if(localStorage.getItem(k)==="light")d.setAttribute("data-theme","light")}catch(e){}
d.setAttribute("data-js","");
function sync(){var b=document.getElementById("theme-toggle");if(b)b.setAttribute("aria-pressed",d.getAttribute("data-theme")==="light"?"true":"false")}
document.addEventListener("DOMContentLoaded",function(){sync();
var p=location.pathname.replace(/\.html$/,"").replace(/(.)\/$/,"$1")||"/";
document.querySelectorAll("[data-current-match]").forEach(function(a){if(a.getAttribute("href")===p)a.setAttribute("aria-current","page")})});
document.addEventListener("click",function(e){
var t=e.target;if(!t||!t.closest||!t.closest("#theme-toggle"))return;
var light=d.getAttribute("data-theme")!=="light";
if(light)d.setAttribute("data-theme","light");else d.removeAttribute("data-theme");
try{localStorage.setItem(k,light?"light":"dark")}catch(e){}
sync();
});
})();`;
