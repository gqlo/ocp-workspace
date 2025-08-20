import json
import matplotlib.pyplot as plt

# deserialize json file, convert json data into python object
def des_json(path):
    with open(path) as fd:
        return json.load(fd)

def time_series_plot(data, labels, title, xlabel, ylabel):
    for i in range(len(data)):
        plt.plot(data[i], label=labels[i])
    plt.xticks([]) 
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.legend(loc='upper center', bbox_to_anchor=(0.5, -0.07),fancybox=True, shadow=True, ncol=len(data))
    plt.ylim(bottom=0)
    plt.tight_layout()
    plt.savefig('./plots/'+ title + '.png')
    plt.show()

def time_series_plot_x(x, data, labels, title, xlabel, ylabel):
    for i in range(len(data)):
        plt.plot(x, data[i], label=labels[i])
    #plt.xticks([]) 
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)
    plt.legend(loc='upper center', bbox_to_anchor=(0.5, -0.17),fancybox=True, shadow=True, ncol=len(data))
    plt.ylim(bottom=0)
    plt.grid()
    plt.tight_layout()
    plt.savefig('./plots/'+ title + '.png')
    plt.show()

# remove the timestamp 
def rm_ts(data):
    res =[]
    for n in data:
       res.append(float(n[1]))
    return res

def sum_cpu_usage(data, nodes, modes):
    res = []
    for n in data:
        if n['metric']['mode'] in modes and n['metric']['instance'] in nodes :
            res.append(rm_ts(n["values"]))
    return [sum(item) for item in zip(*res)]

# add element by element
def sum_by_node(data, nodes):
    res = []
    for d in data:
        if d["metric"]["instance"] in nodes:
            res.append(rm_ts(d["values"]))
    return [sum(item) for item in zip(*res)]

def 

crun_path = "/home/guoqingli/work/jupyter/json-data/crun-liveness-0-alive-1.json"
runc_path = "/home/guoqingli/work/jupyter/json-data/runc-liveness-0-alive-1.json"

crun_base_path = "/home/guoqingli/work/jupyter/json-data/crun-baseline.json"
runc_base_path = "/home/guoqingli/work/jupyter/json-data/runc-baseline.json"

crun_latency_path = "/home/guoqingli/work/jupyter/json-latency/crun/"
runc_latency_path = "/home/guoqingli/work/jupyter/json-latency/runc/"

crun_obj = des_json(crun_path)
runc_obj = des_json(runc_path)

crun_base_obj = des_json(crun_base_path)
runc_base_obj = des_json(runc_base_path)

crun_node_mem = crun_obj['metrics']['node_mem_consumption']['data']
runc_node_mem = runc_obj['metrics']['node_mem_consumption']['data']

crun_node_forks = crun_obj['metrics']['node_forks']['data']
runc_node_forks = runc_obj['metrics']['node_forks']['data']

crun_node_cpu = crun_obj['metrics']['cpu_usage']['data']
runc_node_cpu = runc_obj['metrics']['cpu_usage']['data']

crun_node_base_cpu = crun_base_obj['metrics']['cpu_usage']['data']
runc_node_base_cpu = runc_base_obj['metrics']['cpu_usage']['data']

                                      
# memory consumption
mem_nodes = ['worker-2']
runc_mem = [n/1024**2 for n in sum_by_node(runc_node_mem, mem_nodes)]
crun_mem = [n/1024**2 for n in sum_by_node(crun_node_mem, mem_nodes)]

time_series_plot([runc_mem,crun_mem],['runc', 'crun'], 'node memory consumption - worker', 'time', 'MB')

# forks
fork_node = ["worker-2"]
runc_forks = sum_by_node(runc_node_forks, fork_node)
crun_forks = sum_by_node(crun_node_forks, fork_node)
time_series_plot([runc_forks, crun_forks],['runc', 'crun'], 'node forks - worker', 'time', 'forks/sec')

# overall CPU usage of multiple modes
modes = ['iowait', 'irq', 'nice', 'softirq','system', 'user']
cpu_node = ['worker-2']
runc_cpu = [n * 100 for n in sum_cpu_usage(runc_node_cpu, cpu_node, modes)]
crun_cpu = [n * 100 for n in sum_cpu_usage(crun_node_cpu, cpu_node, modes)]

runc_base_cpu = [n * 100 for n in sum_cpu_usage(runc_node_base_cpu, cpu_node, modes)]
crun_base_cpu = [n * 100 for n in sum_cpu_usage(crun_node_base_cpu, cpu_node, modes)]

time_series_plot([runc_cpu, crun_cpu, runc_base_cpu, crun_base_cpu],['runc', 'crun', 'runc-baseline', 'crun-baseline'], 'overall cpu usage summary - worker', 'time', '%')

# cpu usage of indivisual mode
# cpu_node = ['worker-2']

# # cpu usage of indivisual mode
# for runc_metric, crun_metric in zip(runc_obj['metrics']['cpu_usage']['data'], crun_obj['metrics']['cpu_usage']['data']):
#     time_series_plot([[n * 100 for n in rm_ts(runc_metric['values'])], [n * 100 for n in rm_ts(crun_metric['values'])]],['runc', 'crun'], runc_metric['metric']['mode'], 'time', '%')

crun_lat = []
runc_lat = []
for i in range(1,71):
    crun_lat.append(des_json(crun_latency_path + "{}.json".format(i))['summary']['last_pod_start_time'])
    runc_lat.append(des_json(runc_latency_path + "{}.json".format(i))['summary']['last_pod_start_time'])

x = range(10,710,10)
print(list(x))
time_series_plot_x(x, [runc_lat, crun_lat],['runc', 'crun'], 'pods startup latency', 'no. of pods', 'sec')

