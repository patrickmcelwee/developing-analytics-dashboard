xquery version "1.0-ml";
module namespace trns = "http://marklogic.com/analytics-dashboard/northwind";

declare namespace app = "http://marklogic.com/analytics-dashboard/northwind";

declare function trns:transform(
  $content as map:map,
  $context as map:map
) as map:map*
{
  let $doc := map:get($content, 'value')
  let $doc :=
    typeswitch($doc)
      case document-node() return
        $doc/*
      default return
        $doc

  let $productDoc := cts:search(
    collection('northwind-raw'),
    cts:element-value-query(
      xs:QName('ProductID'),
      string($doc/ProductID)
    )
  )[1]

  let $enriched-doc := element app:envelope {
    element app:headers {
      element app:OrderDetailTotal {
        ($doc/UnitPrice * (1 - $doc/Discount)) * $doc/Quantity
      },
      $productDoc
    },
    element app:original {
      $doc
    }
  }

  let $_ := map:put($content, 'value', document { $enriched-doc })
  return $content
};
