import { ajax } from 'discourse/lib/ajax';

export default Discourse.Route.extend({
  model() {
    return ajax('/admin/seo/topics/templates.json');
  },

  setupController(controller, model) {
    controller.set('templates', model.templates);
  }
});
