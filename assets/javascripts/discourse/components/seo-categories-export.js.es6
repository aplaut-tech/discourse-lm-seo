import { outputExportResult } from 'discourse/lib/export-result';
import { exportEntity } from 'discourse/lib/export-csv';

export default Ember.Component.extend({
  actions: {
    export () {
      exportEntity('categories_seo').then(outputExportResult);
    }
  }
});
