import { ajax } from 'discourse/lib/ajax';

export default Discourse.Route.extend({
  model() {
    return ajax('/admin/seo/robots.json');
  },

  setupController(controller, model) {
    controller.set('robots', model.robots);
  }
});
