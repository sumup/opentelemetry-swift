// Copyright 2020, OpenTelemetry Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import OpenTelemetryApi
@testable import OpenTelemetryProtocolExporter
@testable import OpenTelemetrySdk
import XCTest

class SpanAdapterTests: XCTestCase {
    let traceIdBytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4]
    var traceId: TraceId!
    let spanIdBytes: [UInt8] = [0, 0, 0, 0, 4, 3, 2, 1]
    var spanId: SpanId!
    let tracestate = TraceState()
    var spanContext: SpanContext!

    override func setUp() {
        traceId = TraceId(fromBytes: traceIdBytes)
        spanId = SpanId(fromBytes: spanIdBytes)
        spanContext = SpanContext.create(traceId: traceId, spanId: spanId, traceFlags: TraceFlags(), traceState: tracestate)
    }

    func testToProtoSpan() {
        var testData = SpanData(traceId: traceId, spanId: spanId, name: "GET /api/endpoint", kind: SpanKind.server, startEpochNanos: 12345, endEpochNanos: 12349)
        testData.settingHasEnded(false)
        testData.settingAttributes(["key": AttributeValue.bool(true)])
        testData.settingTotalAttributeCount(2)
        testData.settingEvents([SpanData.Event(name: "my_event", epochNanos: 12347)])
        testData.settingTotalRecordedEvents(3)
        testData.settingLinks([SpanData.Link(context: spanContext)])
        testData.settingTotalRecordedLinks(2)
        testData.settingStatus(.ok)

        let span = SpanAdapter.toProtoSpan(spanData: testData)

        XCTAssertEqual(span.traceID, Data(bytes: traceIdBytes, count: 16))
        XCTAssertEqual(span.spanID, Data(bytes: spanIdBytes, count: 8))
        XCTAssertEqual(span.parentSpanID, Data(repeating: 0, count: 0))
        XCTAssertEqual(span.name, "GET /api/endpoint")
        XCTAssertEqual(span.kind, Opentelemetry_Proto_Trace_V1_Span.SpanKind.server)
        XCTAssertEqual(span.startTimeUnixNano, 12345)
        XCTAssertEqual(span.endTimeUnixNano, 12349)

        var attribute = Opentelemetry_Proto_Common_V1_KeyValue()
        attribute.key = "key"
        attribute.value = Opentelemetry_Proto_Common_V1_AnyValue()
        attribute.value.boolValue = true
        XCTAssertEqual(span.attributes, [attribute])
        XCTAssertEqual(span.droppedAttributesCount, 1)

        var event = Opentelemetry_Proto_Trace_V1_Span.Event()
        event.timeUnixNano = 12347
        event.name = "my_event"
        XCTAssertEqual(span.events, [event])
        XCTAssertEqual(span.droppedEventsCount, 2)

        var link = Opentelemetry_Proto_Trace_V1_Span.Link()
        link.traceID = Data(bytes: traceIdBytes, count: 16)
        link.spanID = Data(bytes: spanIdBytes, count: 8)
        XCTAssertEqual(span.links, [link])
        XCTAssertEqual(span.droppedLinksCount, 1)

        var status = Opentelemetry_Proto_Trace_V1_Status()
        status.code = .ok
        XCTAssertEqual(span.status, status)
    }

    func testToProtoSpanKind() {
        XCTAssertEqual(SpanAdapter.toProtoSpanKind(kind: .internal), Opentelemetry_Proto_Trace_V1_Span.SpanKind.internal)
        XCTAssertEqual(SpanAdapter.toProtoSpanKind(kind: .client), Opentelemetry_Proto_Trace_V1_Span.SpanKind.client)
        XCTAssertEqual(SpanAdapter.toProtoSpanKind(kind: .server), Opentelemetry_Proto_Trace_V1_Span.SpanKind.server)
        XCTAssertEqual(SpanAdapter.toProtoSpanKind(kind: .producer), Opentelemetry_Proto_Trace_V1_Span.SpanKind.producer)
        XCTAssertEqual(SpanAdapter.toProtoSpanKind(kind: .consumer), Opentelemetry_Proto_Trace_V1_Span.SpanKind.consumer)
    }

    func testToProtoStatus() {
        var status = Opentelemetry_Proto_Trace_V1_Status()
        status.code = .unset
        XCTAssertEqual(SpanAdapter.toStatusProto(status: .unset), status)

        status = Opentelemetry_Proto_Trace_V1_Status()
        status.code = .ok
        status.message = "SUCCESS"
        XCTAssertEqual(SpanAdapter.toStatusProto(status: Status.ok.withDescription(description: "SUCCESS")), status)


        status = Opentelemetry_Proto_Trace_V1_Status()
        status.code = .error
        status.message = "ERROR"
        XCTAssertEqual(SpanAdapter.toStatusProto(status: Status.error.withDescription(description: "ERROR")), status)
    }

    func testToProtoSpanEvent() {
        var eventNoAttrib = Opentelemetry_Proto_Trace_V1_Span.Event()
        eventNoAttrib.timeUnixNano = 12345
        eventNoAttrib.name = "test_without_attributes"
        XCTAssertEqual(SpanAdapter.toProtoSpanEvent(event: SpanData.Event(name: "test_without_attributes", epochNanos: 12345)), eventNoAttrib)

        var eventWithAttrib = Opentelemetry_Proto_Trace_V1_Span.Event()
        eventWithAttrib.timeUnixNano = 12345
        eventWithAttrib.name = "test_with_attributes"

        var attribute = Opentelemetry_Proto_Common_V1_KeyValue()
        attribute.key = "key_string"
        attribute.value = Opentelemetry_Proto_Common_V1_AnyValue()
        attribute.value.stringValue = "string"
        eventWithAttrib.attributes = [attribute]

        XCTAssertEqual(SpanAdapter.toProtoSpanEvent(event: SpanData.Event(name: "test_with_attributes", epochNanos: 12345, attributes: ["key_string": AttributeValue.string("string")])), eventWithAttrib)
    }

    func testToProtoSpanLink() {
        var linkNoAttrib = Opentelemetry_Proto_Trace_V1_Span.Link()
        linkNoAttrib.traceID = Data(bytes: traceIdBytes, count: 16)
        linkNoAttrib.spanID = Data(bytes: spanIdBytes, count: 8)
        XCTAssertEqual(SpanAdapter.toProtoSpanLink(link: SpanData.Link(context: spanContext)), linkNoAttrib)

        var linkWithAttrib = Opentelemetry_Proto_Trace_V1_Span.Link()
        linkWithAttrib.traceID = Data(bytes: traceIdBytes, count: 16)
        linkWithAttrib.spanID = Data(bytes: spanIdBytes, count: 8)
        var attribute = Opentelemetry_Proto_Common_V1_KeyValue()
        attribute.key = "key_string"
        attribute.value = Opentelemetry_Proto_Common_V1_AnyValue()
        attribute.value.stringValue = "string"
        linkWithAttrib.attributes = [attribute]
        XCTAssertEqual(SpanAdapter.toProtoSpanLink(link: SpanData.Link(context: spanContext, attributes: ["key_string": AttributeValue.string("string")])), linkWithAttrib)
    }
}
