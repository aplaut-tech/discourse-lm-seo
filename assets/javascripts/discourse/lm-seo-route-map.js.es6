export default {
  resource: 'admin',
  map() {
    this.route('adminSeo', {path: '/seo', resetNamespace: true}, function() {
      this.route('robots', {path: '/widgets'});
      this.route('sitemap', {path: '/sitemap'})
    });
  }
};
