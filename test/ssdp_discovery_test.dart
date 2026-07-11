import 'package:flutter_test/flutter_test.dart';
import 'package:sonority/data/sonos/ssdp_discovery.dart';

void main() {
  test('subnetHosts enumerates the /24 minus self and .0/.255', () {
    final hosts = SsdpDiscovery.subnetHosts('192.168.1.42');
    expect(hosts, hasLength(253));
    expect(hosts.first, '192.168.1.1');
    expect(hosts.last, '192.168.1.254');
    expect(hosts, isNot(contains('192.168.1.42')));
    expect(hosts, isNot(contains('192.168.1.0')));
    expect(hosts, isNot(contains('192.168.1.255')));
    expect(hosts, isNot(contains('192.168.2.1')));
  });
}
