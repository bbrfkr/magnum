import os

from magnum.drivers.heat import k8s_centos7_template_def as kctd


class Centos7K8sTemplateDefinition(kctd.K8sCentos7TemplateDefinition):
    """Kubernetes template for a CentOS 7 VM."""

    @property
    def driver_module_path(self):
        return __name__[:__name__.rindex('.')]

    @property
    def template_path(self):
        return os.path.join(os.path.dirname(os.path.realpath(__file__)),
                            'templates/kubecluster.yaml')
