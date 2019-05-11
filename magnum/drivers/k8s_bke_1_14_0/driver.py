from magnum.drivers.heat import driver
from magnum.drivers.k8s_bke_1_14_0 import template_def


class Driver(driver.HeatDriver):

    @property
    def provides(self):
        return [
            {'server_type': 'vm',
             'os': 'bke-1_14_0',
             'coe': 'kubernetes'},
        ]

    def get_template_definition(self):
        return template_def.Centos7K8sTemplateDefinition()

    def get_monitor(self, context, cluster):
        return None

    def get_scale_manager(self, context, osclient, cluster):
        return None

    def pre_delete_cluster(self, context, cluster):
        return None
