import {ajax} from 'discourse/lib/ajax';
import { outputExportResult } from 'discourse/lib/export-result';
import { exportEntity } from 'discourse/lib/export-csv';

export default Ember.Component.extend({
  actions: {
    import () {
      const input = $('#import-file-input')[0];
      const file = input.files[0];
      const data = new FormData;
      data.append('file', file);

      this.set('importProgress', true);
      ajax('/admin/seo/topics', {
        type: 'POST',
        contentType: false,
        processData: false,
        data: data
      }).then((result) => {
        const report = I18n.t('admin.lm_seo.topics.import_report', {
          success_count: result.success_count,
          error_count: result.error_count
        });
        bootbox.alert(report);
        input.files[0] = undefined;
        this.set('importProgress', false);
      }).catch((error) => {
        this.set('importProgress', false);
      });
    },

    export () {
      exportEntity('topics_seo').then(outputExportResult);
    }
  }
});
