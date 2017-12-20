export default {
  resource: 'admin',

  map() {
    this.route('adminSeo', {path: '/seo', resetNamespace: true}, function() {
      this.route('robots', {path: '/robots'});
      this.route('sitemap', {path: '/sitemap'});
      this.route('topics', {path: '/topics'}, function () {
        this.route('export', {path: '/export'});
        this.route('import', {path: '/import'});
        this.route('templates', {path: '/templates'});
      });
    });
  }
};
