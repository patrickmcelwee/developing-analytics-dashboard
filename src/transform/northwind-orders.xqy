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

  let $customerDoc := cts:search(
    collection('northwind-raw'),
    cts:element-value-query(
      xs:QName('CustomerID'),
      string($doc/CustomerID)
    )
  )[1]

  let $employeeDoc := cts:search(
    collection('northwind-employees'),
    cts:element-value-query(
      xs:QName('EmployeeID'),
      string($doc/EmployeeID)
    )
  )[1]

  let $orderDetailsDocs := cts:search(
    collection('northwind-order-details'),
    cts:element-value-query(
      xs:QName('OrderID'),
      string($doc/OrderID)
    )
  )

  let $orderTotal := fn:sum($orderDetailsDocs//app:OrderDetailTotal)

  let $enriched-doc := element app:envelope {
    element app:headers {
      element app:OrderTotal { $orderTotal },
      $customerDoc,
      $employeeDoc,
      element OrderDetails {
        $orderDetailsDocs
      }
    },
    element app:original {
      $doc
    }
  }

  let $_ := map:put($content, 'value', document { $enriched-doc })
  return $content
};
