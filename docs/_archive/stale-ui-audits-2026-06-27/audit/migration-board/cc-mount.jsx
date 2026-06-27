/* ============================================================
   LANCER — board mount (loaded LAST, after all screens)
   ============================================================ */

(function(){
  const root = document.getElementById('root');
  if (!root || typeof window.MigrationBoard !== 'function') {
    console.error('[cc-mount] MigrationBoard not found');
    return;
  }
  ReactDOM.createRoot(root).render(React.createElement(window.MigrationBoard));
})();