import {ajax} from 'discourse/lib/ajax';

export default Ember.Component.extend({
  actions: {
    save () {
      const robots = this.get('robots');
      const data = {robots};

      this.set('saving', true);
      ajax('/admin/seo/robots.json', {type: 'PUT', data}).then((result) => {
        this.set('saving', false);
      }).catch(() => {
        this.set('saving', false);
      });
    }
  }
});
