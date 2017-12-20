import { ajax } from 'discourse/lib/ajax';

export default Ember.Component.extend({
  actions: {
    import () {
      const input = $('#import-file-input')[0];
      const file = input.files[0];
      const data = new FormData;
      data.append('file', file);

      this.set('importing', true);
      ajax('/admin/seo/topics/import', {
        type: 'POST',
        contentType: false,
        processData: false,
        data: data
      }).then((result) => {
        const report = I18n.t('admin.lm_seo.topics.import.report', {
          success_count: result.success_count,
          error_count: result.error_count
        });
        bootbox.alert(report);
        input.files[0] = undefined;
        this.set('importing', false);
      }).catch((error) => {
        this.set('importing', false);
      });
    }
  }
});
