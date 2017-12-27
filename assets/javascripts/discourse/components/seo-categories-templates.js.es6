import { ajax } from 'discourse/lib/ajax';

export default Ember.Component.extend({
  actions: {
    save () {
      const data = {
        templates: this.get('templates')
      };

      this.set('saving', true);
      ajax('/admin/seo/categories/templates.json', {
        type: 'PUT',
        data: data
      }).then((result) => {
        const report = I18n.t('admin.lm_seo.categories.templates.report');
        bootbox.alert(report);
        this.set('saving', false);
      }).catch((error) => {
        this.set('saving', false);
      });
    }
  }
});
